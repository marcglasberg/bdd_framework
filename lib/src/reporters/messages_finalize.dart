import 'dart:convert';
import 'dart:io';

import 'package:cucumber_messages/cucumber_messages.dart' as messages;

import 'messages_file.dart';
import 'messages_runner_result.dart';

/// Publishes [path] using the actual result of a completed test process.
///
/// The process must have used `--file-reporter=json:<runnerJsonPath>`. Call
/// this only after it exits, passing its unchanged [testExitCode]. The partial
/// at `path.partial` is consumed, even on validation failure. A matching random
/// run ID in the partial and runner log prevents accidental cross-run mixing.
/// These are trusted local inputs, not authenticated evidence: restoring copies
/// of both files or lying about the process status is outside this contract.
///
/// Returns true for confirmed success and false for confirmed test failure.
/// Missing, interrupted, inconsistent or unsupported results throw and leave
/// no final report. Step details remain observations of BDD bodies; the global
/// result covers every test selected by the command, including non-BDD tests.
///
/// Use one reporter per output path and a fresh private directory per command.
/// Do not run concurrent publishers against the same path. Output/input links
/// are rejected, but parent directories must not be changed concurrently.
Future<bool> finalizeMessages({
  required String path,
  required String runnerJsonPath,
  required int testExitCode,
}) async {
  final outputUri = _canonicalUri(path);
  final partialPath = '$path.partial';
  if ({
    outputUri,
    _canonicalUri(partialPath),
  }.contains(_canonicalUri(runnerJsonPath))) {
    throw ArgumentError('Runner JSON must have a separate file path.');
  }
  if (FileSystemEntity.typeSync(runnerJsonPath, followLinks: false) ==
      FileSystemEntityType.link) {
    throw FileSystemException(
      'Runner JSON must not be a link.',
      runnerJsonPath,
    );
  }

  // Also reject filesystem aliases (for example Windows short names or hard
  // links) before invalidating a file which may be the supplied runner input.
  for (final candidate in [path, partialPath]) {
    if (FileSystemEntity.typeSync(candidate, followLinks: false) ==
            FileSystemEntityType.file &&
        FileSystemEntity.typeSync(runnerJsonPath, followLinks: false) ==
            FileSystemEntityType.file &&
        await FileSystemEntity.identical(candidate, runnerJsonPath)) {
      throw ArgumentError('Runner JSON aliases a Messages file.');
    }
  }

  await invalidateMessagesFile(path);
  final partial = _PartialReport(await consumeMessagesFile(partialPath));
  final runnerJson = await readMessagesFile(runnerJsonPath);
  final success = readMessagesRunnerResult(
    runnerJson,
    runId: partial.runId,
    outputUri: outputUri,
    testExitCode: testExitCode,
  );
  if (success && !partial.bodiesPassed) {
    throw const FormatException(
      'Runner success contradicts an incomplete or failing final BDD attempt.',
    );
  }
  final finished = messages.Envelope(
    testRunFinished: messages.TestRunFinished(
      success: success,
      timestamp: messages.dateTimeToTimestamp(DateTime.now()),
      testRunStartedId: partial.runId,
      message:
          'Final result of the complete test command (exit $testExitCode). '
          'Step details describe BDD bodies; setup, teardown and timeout '
          'failures may occur outside those steps.',
    ),
  );
  await writeMessagesFile(path, () sync* {
    yield* partial.lines;
    yield messages.envelopeToJsonString(finished);
  });
  return success;
}

String _canonicalUri(String path) {
  final uri = File(path).absolute.uri.normalizePath().toString();
  return Platform.isWindows ? uri.toLowerCase() : uri;
}

/// Validate the generated subset and execution references before trusting it.
class _PartialReport {
  _PartialReport(String text) : lines = const LineSplitter().convert(text) {
    if (!text.endsWith('\n') || lines.isEmpty || lines.length > 100000) {
      throw const FormatException('Incomplete or oversized Messages partial.');
    }
    final cases = <String, messages.TestCase>{};
    final pickles = <String>{};
    final mappedPickles = <String>{};
    final attempts = <String, _Attempt>{};
    final latest = <String, _Attempt>{};
    var metaSeen = false;
    String? id;
    const types = {
      'meta',
      'source',
      'gherkinDocument',
      'pickle',
      'hook',
      'testRunStarted',
      'testCase',
      'testCaseStarted',
      'testStepStarted',
      'testStepFinished',
      'testCaseFinished',
    };
    for (final line in lines) {
      final Map<String, dynamic> json;
      final messages.Envelope envelope;
      try {
        json = jsonDecode(line) as Map<String, dynamic>;
        envelope = messages.parseEnvelopeJson(line);
      } catch (_) {
        // JSON/parser exceptions can include their source text. Do not copy
        // potentially sensitive test data to the finalizer's error log.
        throw const FormatException('Invalid Cucumber Messages envelope.');
      }
      if (json.length != 1 || !types.contains(json.keys.single)) {
        throw const FormatException(
          'Expected an unfinalized Messages envelope.',
        );
      }
      if (envelope.pickle case final pickle?) {
        if (id != null || !pickles.add(pickle.id)) {
          throw const FormatException('Invalid or duplicate Messages pickle.');
        }
      }
      if (envelope.meta != null) {
        if (metaSeen || envelope.meta!.implementation.name != 'bdd_framework') {
          throw const FormatException('Invalid Messages producer.');
        }
        metaSeen = true;
      }
      if (envelope.testRunStarted case final started?) {
        if (id != null ||
            !RegExp(r'^[0-9a-f]{64}$').hasMatch(started.id ?? '')) {
          throw const FormatException('Expected one unique Messages run ID.');
        }
        id = started.id;
      }
      if (envelope.testCase case final testCase?) {
        if (id == null ||
            testCase.testRunStartedId != id ||
            cases.containsKey(testCase.id) ||
            !pickles.contains(testCase.pickleId) ||
            !mappedPickles.add(testCase.pickleId) ||
            testCase.testSteps.map((s) => s.id).toSet().length !=
                testCase.testSteps.length) {
          throw const FormatException('Invalid Messages test-case references.');
        }
        cases[testCase.id] = testCase;
      }
      if (envelope.testCaseStarted case final started?) {
        final testCase = cases[started.testCaseId];
        final previous = latest[started.testCaseId];
        if (testCase == null ||
            attempts.containsKey(started.id) ||
            started.attempt < 0 ||
            (previous != null &&
                (!previous.finished ||
                    !previous.willBeRetried ||
                    started.attempt <= previous.number))) {
          throw const FormatException('Invalid Messages attempt references.');
        }
        final attempt = _Attempt(
          started.attempt,
          testCase.testSteps.map((s) => s.id).toSet(),
        );
        attempts[started.id] = attempt;
        latest[started.testCaseId] = attempt;
      }
      if (envelope.testStepStarted case final started?) {
        final attempt = attempts[started.testCaseStartedId];
        if (attempt == null ||
            attempt.finished ||
            !attempt.steps.contains(started.testStepId) ||
            !attempt.startedSteps.add(started.testStepId)) {
          throw const FormatException('Invalid Messages step references.');
        }
      }
      if (envelope.testStepFinished case final finished?) {
        final attempt = attempts[finished.testCaseStartedId];
        if (attempt == null ||
            attempt.finished ||
            !attempt.startedSteps.contains(finished.testStepId) ||
            !attempt.finishedSteps.add(finished.testStepId)) {
          throw const FormatException('Invalid Messages step result.');
        }
        final status = finished.testStepResult.status;
        if (status != messages.TestStepResultStatus.passed &&
            status != messages.TestStepResultStatus.skipped) {
          attempt.passed = false;
        }
      }
      if (envelope.testCaseFinished case final finished?) {
        final attempt = attempts[finished.testCaseStartedId];
        if (attempt == null ||
            attempt.finished ||
            attempt.finishedSteps.length != attempt.steps.length) {
          throw const FormatException('Incomplete Messages attempt.');
        }
        attempt.finished = true;
        attempt.willBeRetried = finished.willBeRetried;
      }
    }
    if (!metaSeen ||
        id == null ||
        mappedPickles.length != pickles.length ||
        latest.length != cases.length ||
        attempts.values.any((a) => !a.finished) ||
        latest.values.any((a) => a.willBeRetried)) {
      throw const FormatException('Incomplete Messages run.');
    }
    runId = id;
    bodiesPassed = latest.values.every((a) => a.passed);
  }

  final List<String> lines;
  late final String runId;
  late final bool bodiesPassed;
}

class _Attempt {
  _Attempt(this.number, this.steps);
  final int number;
  final Set<String> steps;
  final startedSteps = <String>{};
  final finishedSteps = <String>{};
  bool passed = true;
  bool finished = false;
  bool willBeRetried = false;
}

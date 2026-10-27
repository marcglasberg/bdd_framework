import 'dart:async';
import 'dart:io';

import 'package:bdd_framework/dart_test.dart';
import 'package:cucumber_messages/cucumber_messages.dart' as messages;
import 'package:test/test.dart';

import 'gherkin_support.dart';
import 'stdout_capture.dart';

void main() {
  late MessagesReporter reporter;

  setUp(() {
    reporter = MessagesReporter();
    BddReporter.set(reporter);
  });

  tearDown(() => BddReporter.set());

  group('structure', () {
    test('writes meta, sources, documents, pickles, test cases and results',
        () async {
      final feature = BddFeature('Shopping cart');
      final bdd = Bdd(feature)
          .scenario('Adding an item')
          .given('an empty cart')
          .when('I add an apple')
          .then('the cart has 1 item')
          .bdd;
      await _run(bdd);

      final report = _Report(reporter.envelopes());

      expect(report.types, [
        'meta',
        'source',
        'gherkinDocument',
        'pickle',
        'hook',
        'testRunStarted',
        'testCase',
        'testCaseStarted',
        for (var i = 0; i < 4; i++) ...['testStepStarted', 'testStepFinished'],
        'testCaseFinished',
        'testRunFinished',
      ]);

      final meta = report.single((e) => e.meta);
      expect(meta.implementation.name, 'bdd_framework');
      expect(meta.runtime.name, 'Dart');
      expect(meta.protocolVersion, isNotEmpty);

      final source = report.single((e) => e.source);
      expect(source.uri, 'shopping_cart.feature');
      expect(source.mediaType,
          messages.SourceMediaType.textXCucumberGherkinPlain);
      expect(
          source.data,
          'Feature: Shopping cart\n\n'
          '  Scenario: Adding an item\n'
          '    Given an empty cart\n'
          '    When I add an apple\n'
          '    Then the cart has 1 item\n');

      final hook = report.single((e) => e.hook);
      expect(hook.name, 'run() callback');
      expect(hook.type, messages.HookType.afterTestCase);

      expect(report.results, [
        'Adding an item #0: an empty cart=PASSED, I add an apple=PASSED, '
            'the cart has 1 item=PASSED, hook=PASSED',
      ]);
      final finished = report.single((e) => e.testRunFinished);
      expect(finished.success, isFalse);
      expect(finished.message, contains('Incomplete'));
      expect(finished.message, contains('final runner result unavailable'));
      report.expectConsistent();
    });

    test('the source is the same Gherkin the FeatureFileReporter exports',
        () async {
      final feature = BddFeature('Export parity',
          description: 'A feature with a description.');
      feature.background.given('a background step');
      final outline = Bdd(feature)
          .scenario('An outline')
          .given('the value <value>')
          .table('items', row(val('name', 'a|b'), val('qty', 1)))
          .note('A note\nwith two lines')
          .when('I use it')
          .then('it works')
          .example(val('value', 1))
          .example(val('value', 'two'))
          .bdd;
      final plain = Bdd(feature).scenario('A plain one').then('ok').bdd;

      final exported = await exportFeature([outline, plain]);
      BddReporter.set(reporter);
      for (final bdd in [outline, plain]) {
        await _run(bdd);
      }

      final report = _Report(reporter.envelopes());
      expect(report.single((e) => e.source).data, exported);
      expect(report.all((e) => e.parseError), isEmpty);
      report.expectConsistent();
    });

    test('every message survives a JSON round trip', () async {
      final feature = BddFeature('Round trip');
      final bdd = Bdd(feature)
          .scenario('Failing <n>')
          .given('a step')
          .code((ctx) => throw StateError('boom'))
          .then('another step')
          .example(val('n', 1))
          .bdd;
      await _run(bdd);

      for (final envelope in reporter.envelopes()) {
        final json = messages.envelopeToJsonString(envelope);
        expect(messages.parseEnvelopeJson(json), envelope, reason: json);
      }
    });

    test('ids are unique and references point to existing messages', () async {
      final feature1 = BddFeature('First');
      feature1.background.given('a background').code((ctx) {});
      final feature2 = BddFeature('Second');
      final bdds = [
        Bdd(feature1).scenario('A').given('x').code((ctx) {}).then('y').bdd,
        Bdd(feature1)
            .scenario('B <n>')
            .then('z <n>')
            .example(val('n', 1))
            .example(val('n', 2))
            .bdd,
        Bdd(feature2).scenario('C').when('w').then('v').bdd,
      ];
      for (final bdd in bdds) {
        await _run(bdd);
      }

      final report = _Report(reporter.envelopes());
      expect(report.all((e) => e.source).map((s) => s.uri),
          ['first.feature', 'second.feature']);
      expect(report.all((e) => e.testCase), hasLength(4));
      report.expectConsistent();
    });
  });

  group('step results', () {
    test('the code of a step decides its result and duration', () async {
      final feature = BddFeature('Durations');
      final bdd = Bdd(feature)
          .scenario('Slow steps')
          .given('a slow step')
          .code((ctx) => Future.delayed(const Duration(milliseconds: 30)))
          .when('a fast step')
          .code((ctx) {})
          .then('a step without code')
          .bdd;
      await _run(bdd);

      final report = _Report(reporter.envelopes());
      expect(report.results, [
        'Slow steps #0: a slow step=PASSED, a fast step=PASSED, '
            'a step without code=PASSED, hook=PASSED',
      ]);
      final durations = report.stepDurations.single;
      expect(durations[0],
          greaterThanOrEqualTo(const Duration(milliseconds: 30)));
      expect(durations[1], lessThan(const Duration(milliseconds: 30)));
      expect(durations[2], Duration.zero);

      // Each step starts when the one before it finished.
      final started = report.all((e) => e.testStepStarted).toList();
      final finished = report.all((e) => e.testStepFinished).toList();
      for (var i = 1; i < started.length; i++) {
        expect(
          _time(started[i].timestamp)
              .isBefore(_time(finished[i - 1].timestamp)),
          isFalse,
        );
      }
    });

    test('a failing step fails, and the steps after it are skipped', () async {
      final feature = BddFeature('Failures');
      final bdd = Bdd(feature)
          .scenario('Failing step')
          .given('a passing step')
          .code((ctx) {})
          .when('a failing step')
          .code((ctx) => throw StateError('the failure'))
          .then('a step with code')
          .code((ctx) {})
          .and('a step without code')
          .bdd;
      await _run(bdd);

      final report = _Report(reporter.envelopes());
      expect(report.results, [
        'Failing step #0: a passing step=PASSED, a failing step=FAILED, '
            'a step with code=SKIPPED, a step without code=SKIPPED, '
            'hook=SKIPPED',
      ]);

      final result = report.stepResults.single[1];
      expect(result.message, startsWith('Bad state: the failure\n'));
      expect(result.exception!.type, 'StateError');
      expect(result.exception!.message, 'Bad state: the failure');
      // Tools like the HTML formatter show only the stack trace, when there
      // is one, so it must start with the error.
      expect(result.exception!.stackTrace, result.message);
      expect(result.exception!.stackTrace, contains('messages_reporter_test'));
      expect(report.single((e) => e.testRunFinished).success, isFalse);
    });

    test('a failing .run() callback fails the hook, not the steps', () async {
      final feature = BddFeature('Callback');
      final bdd = Bdd(feature)
          .scenario('Failing callback')
          .given('a step')
          .then('another step')
          .bdd;
      await _run(bdd, (ctx) async {
        await Future<void>.delayed(Duration.zero);
        throw TestFailure('Expected: 1, Actual: 2');
      });

      final report = _Report(reporter.envelopes());
      expect(report.results, [
        'Failing callback #0: a step=PASSED, another step=PASSED, hook=FAILED',
      ]);
      expect(report.stepResults.single.last.message,
          startsWith('Expected: 1, Actual: 2'));
      expect(report.single((e) => e.testRunFinished).success, isFalse);
    });

    test('a step with several code blocks fails if any of them fails',
        () async {
      final feature = BddFeature('Several blocks');
      final bdd = Bdd(feature)
          .scenario('Two blocks')
          .given('a step with two blocks')
          .code((ctx) {})
          .code((ctx) => throw StateError('second block'))
          .then('the next step')
          .bdd;
      await _run(bdd);

      expect(_Report(reporter.envelopes()).results, [
        'Two blocks #0: a step with two blocks=FAILED, the next step=SKIPPED, '
            'hook=SKIPPED',
      ]);
    });

    test('notes are not steps, and tables belong to the step before them',
        () async {
      final feature = BddFeature('Notes and tables');
      final bdd = Bdd(feature)
          .scenario('With a table')
          .note('This is a note')
          .and('these items')
          .table('items', row(val('name', 'apple'), val('qty', 2)))
          .code((ctx) => throw StateError('table code'))
          .note('Another note')
          .then('nothing else')
          .bdd;
      await _run(bdd);

      final report = _Report(reporter.envelopes());
      expect(report.results, [
        'With a table #0: these items=FAILED, nothing else=SKIPPED, '
            'hook=SKIPPED',
      ]);
      final pickleStep = report.single((e) => e.pickle).steps.first;
      expect(
        pickleStep.argument!.dataTable!.rows
            .map((row) => row.cells.map((cell) => cell.value).toList()),
        [
          ['name', 'qty'],
          ['apple', '2'],
        ],
      );
    });

    test('Background steps are the first steps of every test case', () async {
      final feature = BddFeature('With background');
      feature.background
          .given('a background step')
          .code((ctx) => throw StateError('background failure'));
      final bdd1 = Bdd(feature).scenario('First').then('a').bdd;
      final bdd2 = Bdd(feature).scenario('Second').when('b').then('c').bdd;
      await _run(bdd1);
      await _run(bdd2);

      expect(_Report(reporter.envelopes()).results, [
        'First #0: a background step=FAILED, a=SKIPPED, hook=SKIPPED',
        'Second #0: a background step=FAILED, b=SKIPPED, c=SKIPPED, '
            'hook=SKIPPED',
      ]);
    });

    test('a step that never finished fails', () async {
      final feature = BddFeature('Timeout');
      final never = Completer<void>();
      final bdd = Bdd(feature)
          .scenario('Hanging')
          .given('a step that hangs')
          .code((ctx) => never.future)
          .then('the next step')
          .bdd;
      final invocations = <TestInvocation>[];
      BddRunner().run(bdd, (ctx) {}, invocations.add, null);
      unawaited(_quietly(invocations.single.body));
      await Future<void>.delayed(Duration.zero);

      final report = _Report(reporter.envelopes());
      expect(report.results, [
        'Hanging #0: a step that hangs=FAILED, the next step=SKIPPED, '
            'hook=SKIPPED',
      ]);
      expect(report.stepResults.single.first.message,
          'The step did not finish. It may have timed out.');
      expect(report.single((e) => e.testRunFinished).success, isFalse);
    });
  });

  group('test cases', () {
    test('each example row is a separate test case', () async {
      final feature = BddFeature('Outline');
      final bdd = Bdd(feature)
          .scenario('Checking <number>')
          .given('the number <number>')
          .then('it is positive')
          .example(val('number', 1))
          .example(val('number', -1))
          .bdd;
      await _run(bdd, (ctx) {
        if ((ctx.example.val('number') as int) < 0) {
          throw StateError('negative');
        }
      });

      final report = _Report(reporter.envelopes());
      expect(report.results, [
        'Checking 1 #0: the number 1=PASSED, it is positive=PASSED, '
            'hook=PASSED',
        'Checking -1 #0: the number -1=PASSED, it is positive=PASSED, '
            'hook=FAILED',
      ]);
      expect(report.single((e) => e.testRunFinished).success, isFalse);
      report.expectConsistent();
    });

    test('a retry is a new attempt of the same test case', () async {
      final feature = BddFeature('Retries');
      var runs = 0;
      final bdd = Bdd(feature)
          .scenario('Flaky')
          .given('a flaky step')
          .code((ctx) {
            if (++runs == 1) throw StateError('flaky');
          })
          .then('it passes eventually')
          .bdd;
      await _runWithRetries(bdd, (ctx) {}, 2);

      final report = _Report(reporter.envelopes());
      expect(report.results, [
        'Flaky #0: a flaky step=FAILED, it passes eventually=SKIPPED, '
            'hook=SKIPPED',
        'Flaky #1: a flaky step=PASSED, it passes eventually=PASSED, '
            'hook=PASSED',
      ]);
      expect(
        report.all((e) => e.testCaseFinished).map((f) => f.willBeRetried),
        [true, false],
      );
      final started = report.all((e) => e.testCaseStarted).toList();
      expect(started[0].testCaseId, started[1].testCaseId);
      expect(report.single((e) => e.testRunFinished).success, isFalse);
    });

    test('a skipped BDD has all its steps skipped', () async {
      final feature = BddFeature('Skipping');
      final skipped =
          Bdd(feature).scenario('Skipped').given('a').then('b').bdd..skip;
      final ran = Bdd(feature).scenario('Ran').then('c').bdd;
      await _run(skipped);
      await _run(ran);

      final report = _Report(reporter.envelopes());
      expect(report.results, [
        'Ran #0: c=PASSED, hook=PASSED',
        'Skipped #0: a=SKIPPED, b=SKIPPED, hook=SKIPPED',
      ]);
      expect(report.single((e) => e.testRunFinished).success, isFalse);
      report.expectConsistent();
    });

    test('runs are reported in the order they started', () async {
      final feature = BddFeature('Order');
      final first = Bdd(feature).scenario('First').then('a').bdd;
      final second = Bdd(feature).scenario('Second').then('b').bdd;
      final invocations = <TestInvocation>[];
      BddRunner().run(first, (ctx) {}, invocations.add, null);
      BddRunner().run(second, (ctx) {}, invocations.add, null);
      await _quietly(invocations[1].body);
      await Future<void>.delayed(const Duration(milliseconds: 2));
      await _quietly(invocations[0].body);

      expect(_Report(reporter.envelopes()).results, [
        'Second #0: b=PASSED, hook=PASSED',
        'First #0: a=PASSED, hook=PASSED',
      ]);
    });
  });

  group('BDDs that are not Gherkin scenarios', () {
    test('a failed BDD without a scenario rejects an incomplete report',
        () async {
      // Without a scenario, Gherkin reads the steps as the feature description.
      final feature = BddFeature('No scenario');
      final bdd = Bdd(feature).given('a step').then('another').bdd;
      final other = Bdd(BddFeature('Other')).scenario('Fine').then('ok').bdd;
      await _run(bdd, (_) => throw StateError('must not disappear'));
      await _run(other);

      expect(bdd.executions.single.passed, isFalse);
      expect(
        reporter.envelopes,
        throwsA(isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('BDDs do not match'),
        )),
      );
    });
  });

  group('report()', () {
    test('writes one message per line, creating the directories', () async {
      final temporary = await Directory.systemTemp.createTemp('bdd-messages-');
      final directory = Directory(await temporary.resolveSymbolicLinks());
      addTearDown(() => directory.delete(recursive: true));
      final path = '${directory.path}/nested/dir/messages.ndjson';
      reporter = MessagesReporter(path: path);
      BddReporter.set(reporter);

      final feature = BddFeature('File output');
      await _run(Bdd(feature).scenario('Written').then('to a file').bdd);

      final output = await captureStdout(reporter.report);
      expect(output, contains('Cucumber Messages saved in $path'));

      final lines = File(path).readAsLinesSync();
      final envelopes = lines.map(messages.parseEnvelopeJson).toList();
      expect(envelopes, hasLength(reporter.envelopes().length));
      expect(envelopes.first.meta, isNotNull);
      expect(envelopes.last.testRunFinished, isNotNull);
      expect(_Report(envelopes).results, [
        'Written #0: to a file=PASSED, hook=PASSED',
      ]);
    });

    test('propagates failure when it cannot write the file', () async {
      final temporary = await Directory.systemTemp.createTemp('bdd-messages-');
      final directory = Directory(await temporary.resolveSymbolicLinks());
      addTearDown(() => directory.delete(recursive: true));
      // A directory can't be opened as a file.
      reporter = MessagesReporter(path: directory.path);
      BddReporter.set(reporter);

      await expectLater(reporter.report(), throwsA(isA<FileSystemException>()));
    });

    test('a serialization failure removes the previous report and propagates',
        () async {
      final temporary = await Directory.systemTemp.createTemp('bdd-messages-');
      final directory = Directory(await temporary.resolveSymbolicLinks());
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/messages.ndjson');
      file.writeAsStringSync('old report');
      reporter = MessagesReporter(path: file.path);
      BddReporter.set(reporter);
      final error = _UnprintableError();
      await _run(
        Bdd(BddFeature('Serialization')).scenario('Failed').then('x').bdd,
        (_) => throw error,
      );
      error.throwOnPrint = true;
      await expectLater(reporter.report(), throwsStateError);
      expect(file.existsSync(), isFalse);
    });
  });
}

class _UnprintableError extends Error {
  bool throwOnPrint = false;
  @override
  String toString() {
    if (throwOnPrint) throw StateError('Cannot serialize this error');
    return 'Synthetic test failure';
  }
}

/// Runs [bdd] like `package:test` would, with [callback] as the `.run()`
/// callback. Skipped BDDs don't run.
Future<void> _run(BddFramework bdd, [CodeRun? callback]) =>
    _runWithRetries(bdd, callback ?? (ctx) {}, 0);

/// Like [_run], but a failing run is retried up to [retries] times.
Future<void> _runWithRetries(
    BddFramework bdd, CodeRun callback, int retries) async {
  final invocations = <TestInvocation>[];
  BddRunner().run(bdd, callback, invocations.add, (error, stackTrace) {});
  for (final invocation in invocations) {
    if (invocation.skip ?? false) continue;
    for (var attempt = 0; attempt <= retries; attempt++) {
      await _quietly(invocation.body);
      if (bdd.executions.last.passed) break;
    }
  }
}

/// Runs [body] without printing the console output of the BDDs.
Future<void> _quietly(Future<void> Function() body) => runZoned(
      body,
      zoneSpecification: ZoneSpecification(print: (_, __, ___, ____) {}),
    );

DateTime _time(messages.Timestamp timestamp) =>
    messages.timestampToDateTime(timestamp);

/// Reads a list of envelopes, to check them in tests.
class _Report {
  _Report(this.envelopes);

  final List<messages.Envelope> envelopes;

  Iterable<T> all<T extends Object>(T? Function(messages.Envelope) field) =>
      envelopes.map(field).nonNulls;

  T single<T extends Object>(T? Function(messages.Envelope) field) =>
      all(field).single;

  /// The type of each envelope, like `pickle` or `testCase`.
  List<String> get types =>
      [for (final envelope in envelopes) envelope.toJson().keys.single];

  Map<String, messages.Pickle> get _pickles =>
      {for (final pickle in all((e) => e.pickle)) pickle.id: pickle};

  Map<String, messages.TestCase> get _testCases =>
      {for (final testCase in all((e) => e.testCase)) testCase.id: testCase};

  /// For each test case attempt, in order: the pickle name, the attempt, and
  /// the status of each step, like `name #0: step=PASSED, hook=PASSED`.
  List<String> get results {
    final pickleSteps = {
      for (final pickle in all((e) => e.pickle))
        for (final step in pickle.steps) step.id: step,
    };
    final testSteps = {
      for (final testCase in all((e) => e.testCase))
        for (final step in testCase.testSteps) step.id: step,
    };
    final pickles = _pickles;
    final testCases = _testCases;

    return [
      for (final started in all((e) => e.testCaseStarted))
        () {
          final testCase = testCases[started.testCaseId]!;
          final pickle = pickles[testCase.pickleId]!;
          final steps = [
            for (final finished in all((e) => e.testStepFinished))
              if (finished.testCaseStartedId == started.id)
                () {
                  final step = testSteps[finished.testStepId]!;
                  final name = step.hookId != null
                      ? 'hook'
                      : pickleSteps[step.pickleStepId]!.text;
                  return '$name=${finished.testStepResult.status.value}';
                }(),
          ];
          return '${pickle.name} #${started.attempt}: ${steps.join(', ')}';
        }(),
    ];
  }

  /// The step results of each test case attempt.
  List<List<messages.TestStepResult>> get stepResults => [
        for (final started in all((e) => e.testCaseStarted))
          [
            for (final finished in all((e) => e.testStepFinished))
              if (finished.testCaseStartedId == started.id)
                finished.testStepResult,
          ],
      ];

  /// The step durations of each test case attempt.
  List<List<Duration>> get stepDurations => [
        for (final results in stepResults)
          [
            for (final result in results)
              messages.durationMessageToDuration(result.duration),
          ],
      ];

  /// Checks what Cucumber tools expect: unique ids, and references to
  /// messages that exist and come before.
  void expectConsistent() {
    final seen = <String>{};
    void declare(String id) {
      expect(seen.add(id), isTrue, reason: 'Duplicate id $id');
    }

    void expectDeclared(String? id) {
      expect(id, isNotNull);
      expect(seen, contains(id), reason: 'Unknown id $id');
    }

    final pickleStepIds = <String>{};
    for (final envelope in envelopes) {
      if (envelope.pickle case final pickle?) {
        declare(pickle.id);
        for (final step in pickle.steps) {
          declare(step.id);
          pickleStepIds.add(step.id);
        }
      }
      if (envelope.hook case final hook?) declare(hook.id);
      if (envelope.testRunStarted case final started?) declare(started.id!);
      if (envelope.testCase case final testCase?) {
        declare(testCase.id);
        expectDeclared(testCase.pickleId);
        expectDeclared(testCase.testRunStartedId);
        final pickle = _pickles[testCase.pickleId]!;
        final steps = testCase.testSteps
            .where((step) => step.pickleStepId != null)
            .map((step) => step.pickleStepId)
            .toList();
        expect(steps, pickle.steps.map((step) => step.id));
        for (final step in testCase.testSteps) {
          declare(step.id);
          if (step.hookId != null) expectDeclared(step.hookId);
        }
      }
      if (envelope.testCaseStarted case final started?) {
        declare(started.id);
        expectDeclared(started.testCaseId);
      }
      if (envelope.testStepStarted case final started?) {
        expectDeclared(started.testCaseStartedId);
        expectDeclared(started.testStepId);
      }
      if (envelope.testStepFinished case final finished?) {
        expectDeclared(finished.testCaseStartedId);
        expectDeclared(finished.testStepId);
      }
      if (envelope.testCaseFinished case final finished?) {
        expectDeclared(finished.testCaseStartedId);
      }
      if (envelope.testRunFinished case final finished?) {
        expectDeclared(finished.testRunStartedId);
      }
    }

    // Every test case started is finished, and every step of it has a result.
    expect(all((e) => e.testCaseFinished), hasLength(all((e) => e.testCaseStarted).length));
    final testCases = _testCases;
    for (final started in all((e) => e.testCaseStarted)) {
      expect(
        all((e) => e.testStepFinished)
            .where((f) => f.testCaseStartedId == started.id)
            .map((f) => f.testStepId),
        testCases[started.testCaseId]!.testSteps.map((step) => step.id),
      );
    }
  }
}

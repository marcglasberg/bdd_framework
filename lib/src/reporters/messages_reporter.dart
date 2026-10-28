import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:collection/collection.dart';
import 'package:cucumber_messages/cucumber_messages.dart' as messages;

import '../core.dart';
import 'gherkin_source.dart';
import 'messages_file.dart';
import 'messages_gherkin.dart';

/// Writes the results of the BDDs as
/// [Cucumber Messages](https://github.com/cucumber/messages), in an NDJSON
/// file (one JSON message per line).
///
/// The file has the Gherkin of each feature, the same that the
/// [FeatureFileReporter] writes, and the result of each run of each scenario:
/// which steps passed, failed or were skipped, how long each step took, and
/// the errors. Tools that read Cucumber Messages can then use it. For example,
/// [Cucumber's HTML formatter](https://github.com/cucumber/html-formatter)
/// turns it into an HTML report.
///
/// Example:
///
/// ```dart
/// void main() async {
///   BddReporter.set(MessagesReporter(path: './gen_reports/messages.ndjson'));
///   group('favorites_test', favorites_test.main);
///   await BddReporter.reportAll();
/// }
/// ```
///
/// How the BDD results map to Cucumber results:
///
/// * Each example row of a BDD is a separate test case, like a Cucumber
///   Scenario Outline. Each retry is a new attempt of the same test case.
///
/// * The code you add to a step with `.code()` is the code of that step: the
///   step fails if its code throws, and its duration is how long the code took.
///   The steps after a failing step are skipped.
///
/// * A step with no code passes, unless a step before it failed, in which case
///   it's skipped.
///
/// * The callback you give to `.run()` belongs to no step, so it's reported as
///   an `After` hook named `run() callback`. A hook that passes is usually
///   hidden by Cucumber tools, but a hook that fails fails the test case and
///   shows the error.
///
/// * A BDD that was skipped, or that didn't run (for example, because of
///   `.only`), is reported with all its steps skipped.
///
/// [report] writes a partial snapshot to `path.partial`, without a
/// `testRunFinished` message. Run the tests with `--file-reporter=json:...`,
/// then use `dart run bdd_framework:finalize_messages` after the process exits
/// to publish [path] with the actual runner result. See the README for commands.
/// Setup/teardown failures and timeouts cannot be determined from BDD bodies
/// alone. An interrupted or unverifiable run remains incomplete, not failed.
///
/// Reports contain scenario data, errors and stack traces. Store them in a
/// trusted private directory, redact sensitive test data before recording it,
/// and review them before sharing. See the README for the output security
/// policy and size limits.
class MessagesReporter extends BddReporter {
  /// Creates a reporter whose finalized Cucumber Messages will be at [path].
  /// The intermediate file is `path.partial`. Directories are created as needed.
  MessagesReporter({this.path = './gen_messages/messages.ndjson'});

  /// The path of the final NDJSON file, published by the finalizer.
  final String path;

  @override
  Future<void> report() async {
    // Remove old final output even if generation or serialization fails.
    await invalidateMessagesFile(path);
    final runId = _newRunId();
    await writeMessagesFile(
      '$path.partial',
      () => _MessagesBuilder(
        features.toList(),
        normalizeFileName,
        runId,
      ).build().map(messages.envelopeToJsonString),
    );
    // print(), unlike stdout.writeln(), is captured by package:test's JSON
    // reporter. This binds the partial to the execution that produced it.
    final uri = File(path).absolute.uri.normalizePath().toString();
    print(
      'bdd_framework.messages.v1:${jsonEncode({'id': runId, 'output': Platform.isWindows ? uri.toLowerCase() : uri})}',
    );
    stdout.writeln(
      'Partial Cucumber Messages saved in $path.partial; '
      'finalize after the test process exits.',
    );
  }

  /// The Cucumber Messages of all the BDDs this reporter got, in the order
  /// they are written to the partial file. No global result is declared here.
  List<messages.Envelope> envelopes() => _MessagesBuilder(
    features.toList(),
    normalizeFileName,
    _newRunId(),
  ).build();
}

String _newRunId() {
  final random = Random.secure();
  return List.generate(
    32,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

/// The protocol version of the Cucumber Messages this reporter writes.
const _protocolVersion = '34.2.1';

/// A Gherkin step, or the `.run()` callback, of a BDD, and the code blocks it
/// runs.
class _PlannedStep {
  _PlannedStep({required this.isHook});

  /// Whether this is the hook that runs the `.run()` callbacks, instead of a
  /// Gherkin step.
  final bool isHook;

  /// The code blocks of the step. The hook usually has none, since the
  /// callbacks belong to no code term.
  final List<BddCodeTerm> codeTerms = [];

  /// The id of the pickle step this step runs. `null` for the hook.
  String? pickleStepId;

  late final String testStepId;
}

/// One test case: a BDD, or one example row of a BDD.
class _TestCasePlan {
  _TestCasePlan(this.pickleId, this.steps, this.executions)
      : lastAttempt = executions.fold<int>(
          0,
          (latest, run) => run.attempt > latest ? run.attempt : latest,
        );

  final String pickleId;
  final List<_PlannedStep> steps;
  final List<BddExecution> executions;
  final int lastAttempt;

  late final String testCaseId;
}

/// The result of one step in one run.
class _StepOutcome {
  _StepOutcome(
    this.status, {
    this.duration = Duration.zero,
    this.startedAt,
    this.error,
    this.stackTrace,
    this.message,
  });

  final messages.TestStepResultStatus status;
  final Duration duration;
  final DateTime? startedAt;
  final Object? error;
  final StackTrace? stackTrace;
  final String? message;

  bool get failed => status == messages.TestStepResultStatus.failed;
}

class _MessagesBuilder {
  _MessagesBuilder(this.features, this.fileNameOf, this.runId);

  final List<BddFeature> features;
  final String Function(String title) fileNameOf;
  final String runId;

  final List<messages.Envelope> _envelopes = [];
  final GherkinMessageBudget _gherkinBudget = GherkinMessageBudget();
  int _nextId = 0;

  String _id() => '${_nextId++}';

  void _add(messages.Envelope envelope) {
    if (_envelopes.length >= 100000) {
      throw StateError('Cucumber Messages exceeded the 100000 envelope limit.');
    }
    _envelopes.add(envelope);
  }

  List<messages.Envelope> build() {
    _add(messages.Envelope(meta: _meta()));

    final plans = <_TestCasePlan>[];
    for (final feature in features) {
      plans.addAll(_planFeature(feature));
    }

    String? hookId;
    if (plans.any((plan) => plan.steps.any((step) => step.isHook))) {
      hookId = _id();
      _add(messages.Envelope(
        hook: messages.Hook(
          id: hookId,
          name: 'run() callback',
          sourceReference: const messages.SourceReference(),
          type: messages.HookType.afterTestCase,
        ),
      ));
    }

    final runs = <(_TestCasePlan, BddExecution)>[];
    for (final plan in plans) {
      for (final execution in plan.executions) {
        if (runs.length >= 10000) {
          throw StateError('Cucumber Messages exceeded the 10000 run limit.');
        }
        runs.add((plan, execution));
      }
    }
    runs.sort((a, b) => a.$2.startedAt.compareTo(b.$2.startedAt));

    final testRunStartedId = runId;
    var clock = runs.isEmpty ? DateTime.now() : runs.first.$2.startedAt;
    _add(messages.Envelope(
      testRunStarted: messages.TestRunStarted(
        id: testRunStartedId,
        timestamp: messages.dateTimeToTimestamp(clock),
      ),
    ));

    for (final plan in plans) {
      plan.testCaseId = _id();
      for (final step in plan.steps) {
        step.testStepId = _id();
      }
      _add(messages.Envelope(
        testCase: messages.TestCase(
          id: plan.testCaseId,
          pickleId: plan.pickleId,
          testRunStartedId: testRunStartedId,
          testSteps: [
            for (final step in plan.steps)
              step.isHook
                  ? messages.TestStep(id: step.testStepId, hookId: hookId)
                  : messages.TestStep(
                      id: step.testStepId,
                      pickleStepId: step.pickleStepId,
                      stepDefinitionIds: const [],
                      stepMatchArgumentsLists: const [],
                    ),
          ],
        ),
      ));
    }

    for (final (plan, execution) in runs) {
      final willBeRetried = plan.lastAttempt > execution.attempt;
      final (finishedAt, _) =
          _reportRun(plan, execution, willBeRetried: willBeRetried);
      if (finishedAt.isAfter(clock)) clock = finishedAt;
    }

    // The BDDs that didn't run are reported with all their steps skipped.
    for (final plan in plans.where((plan) => plan.executions.isEmpty)) {
      _reportSkipped(plan, clock);
    }

    return _envelopes;
  }

  messages.Meta _meta() {
    final dartVersion = Platform.version.split(' ').first;
    final cpu = RegExp(r'"[a-z]+_(\w+)"').firstMatch(Platform.version)?[1];
    return messages.Meta(
      protocolVersion: _protocolVersion,
      implementation: const messages.Product(name: 'bdd_framework'),
      runtime: messages.Product(name: 'Dart', version: dartVersion),
      os: messages.Product(
        name: Platform.operatingSystem,
        version: Platform.operatingSystemVersion,
      ),
      cpu: messages.Product(name: cpu ?? 'unknown'),
    );
  }

  /// Adds the source, Gherkin document and pickles of [feature], and returns
  /// its test cases.
  List<_TestCasePlan> _planFeature(BddFeature feature) {
    final uri = '${fileNameOf(feature.title)}.feature';
    final source = gherkinSource(feature, maxLength: 1024 * 1024);
    final envelopes = safeGherkinMessages(source, uri, _id,
        budget: _gherkinBudget);
    for (final envelope in envelopes) {
      _add(envelope);
    }

    final errors = [
      for (final envelope in envelopes)
        if (envelope.parseError != null) envelope.parseError!.message,
    ];
    if (errors.isNotEmpty) {
      throw FormatException(
        'Cannot report feature "${feature.title}": '
        'invalid Gherkin (${errors.join('; ')}).',
      );
    }

    final document = envelopes
        .map((envelope) => envelope.gherkinDocument)
        .nonNulls
        .single;
    final pickles =
        envelopes.map((envelope) => envelope.pickle).nonNulls.toList();
    // The BDD DSL has no Rule. A Rule introduced through description text can
    // otherwise hide real scenarios from the root-only positional mapping.
    if (document.feature?.children.any((child) => child.rule != null) ?? false) {
      throw const FormatException('Cannot map Gherkin Rules to BDD scenarios.');
    }
    final scenarios = [
      for (final child in document.feature?.children ?? <messages.FeatureChild>[])
        if (child.scenario != null) child.scenario!,
    ];
    final bdds = feature.bdds;

    if (scenarios.length != bdds.length) {
      throw FormatException(
        'Cannot report feature "${feature.title}": '
        '${bdds.length} BDDs do not match ${scenarios.length} scenarios.',
      );
    }

    final plans = <_TestCasePlan>[];
    final mappedPickles = <String>{};
    for (var i = 0; i < bdds.length; i++) {
      final bdd = bdds[i];
      final scenario = scenarios[i];
      final executionsByExample = <int?, List<BddExecution>>{};
      for (final execution in bdd.executions) {
        (executionsByExample[execution.exampleIndex] ??= []).add(execution);
      }
      final rowIds = [
        for (final examples in scenario.examples)
          for (final row in examples.tableBody) row.id,
      ];

      final scenarioPickles = pickles
          .where((pickle) => pickle.astNodeIds.first == scenario.id)
          .toList();
      final exampleCount = bdd.numberOfExamples();
      if (scenarioPickles.length != (exampleCount == 0 ? 1 : exampleCount) ||
          rowIds.length != exampleCount) {
        throw FormatException(
          'Cannot report scenario "${scenario.name}": '
          'its Gherkin examples do not match the BDD examples.',
        );
      }
      final mappedExamples = <int?>{};
      for (final pickle in scenarioPickles) {
        if (!mappedPickles.add(pickle.id)) {
          throw const FormatException('A Gherkin test case was mapped twice.');
        }
        final steps = _stepsOf(feature.backgroundFramework, bdd);
        final gherkinSteps = steps.where((step) => !step.isHook).toList();
        if (gherkinSteps.length != pickle.steps.length) {
          throw FormatException(
            'Cannot report scenario "${scenario.name}": '
            '${gherkinSteps.length} BDD steps do not match '
            '${pickle.steps.length} Gherkin steps.',
          );
        }
        for (var s = 0; s < gherkinSteps.length; s++) {
          gherkinSteps[s].pickleStepId = pickle.steps[s].id;
        }

        final exampleIndex = (pickle.astNodeIds.length > 1)
            ? rowIds.indexOf(pickle.astNodeIds[1])
            : null;
        if (exampleIndex == -1 || !mappedExamples.add(exampleIndex)) {
          throw FormatException(
            'Cannot report scenario "${scenario.name}": '
            'ambiguous example mapping.',
          );
        }
        plans.add(
          _TestCasePlan(
            pickle.id,
            steps,
            executionsByExample.remove(exampleIndex) ?? const [],
          ),
        );
      }
      if (executionsByExample.isNotEmpty) {
        throw FormatException(
          'Cannot report scenario "${scenario.name}": '
          'some recorded executions have no Gherkin test case.',
        );
      }
    }
    if (mappedPickles.length != pickles.length) {
      throw const FormatException('Some Gherkin test cases have no BDD mapping.');
    }
    return plans;
  }

  /// The Gherkin steps of [bdd], including the ones of its [background], with
  /// the code blocks of each step. Then, if the BDD has `.run()` callbacks, a
  /// hook that runs them.
  List<_PlannedStep> _stepsOf(BddFramework? background, BddFramework bdd) {
    final steps = <_PlannedStep>[];

    // Code that comes before any step (only possible after a note) belongs to
    // the next step.
    final pending = <BddCodeTerm>[];

    for (final term in [...?background?.terms, ...bdd.terms]) {
      if (term is BddCodeTerm) {
        if (steps.isEmpty)
          pending.add(term);
        else
          steps.last.codeTerms.add(term);
      } else if (_isStep(term)) {
        steps.add(_PlannedStep(isHook: false)..codeTerms.addAll(pending));
        pending.clear();
      }
    }

    if (bdd.codeRuns.isNotEmpty || pending.isNotEmpty) {
      steps.add(_PlannedStep(isHook: true)..codeTerms.addAll(pending));
    }

    return steps;
  }

  static bool _isStep(Object term) =>
      (term is BddGiven || term is BddWhen || term is BddThen) &&
      !(term as BddTerm).isNote;

  /// Adds the messages of one run of [plan]. Returns when it finished, and
  /// whether it failed.
  (DateTime, bool) _reportRun(
    _TestCasePlan plan,
    BddExecution execution, {
    required bool willBeRetried,
  }) {
    final testCaseStartedId = _id();
    _add(messages.Envelope(
      testCaseStarted: messages.TestCaseStarted(
        id: testCaseStartedId,
        testCaseId: plan.testCaseId,
        attempt: execution.attempt - 1,
        timestamp: messages.dateTimeToTimestamp(execution.startedAt),
      ),
    ));

    var clock = execution.startedAt;
    var failed = false;

    for (final step in plan.steps) {
      final outcome = _outcomeOf(step, execution, failedBefore: failed);
      var startedAt = outcome.startedAt ?? clock;
      if (startedAt.isBefore(clock)) startedAt = clock;
      final finishedAt = startedAt.add(outcome.duration);
      clock = finishedAt;
      if (outcome.failed) failed = true;
      _addStep(testCaseStartedId, step, outcome, startedAt, finishedAt);
    }

    final duration = execution.duration;
    if (duration != null) {
      final finishedAt = execution.startedAt.add(duration);
      if (finishedAt.isAfter(clock)) clock = finishedAt;
    }

    _add(messages.Envelope(
      testCaseFinished: messages.TestCaseFinished(
        testCaseStartedId: testCaseStartedId,
        timestamp: messages.dateTimeToTimestamp(clock),
        willBeRetried: willBeRetried,
      ),
    ));

    return (clock, failed || !execution.passed);
  }

  /// Adds the messages of a test case that didn't run, with all its steps
  /// skipped.
  void _reportSkipped(_TestCasePlan plan, DateTime at) {
    final testCaseStartedId = _id();
    final timestamp = messages.dateTimeToTimestamp(at);
    _add(messages.Envelope(
      testCaseStarted: messages.TestCaseStarted(
        id: testCaseStartedId,
        testCaseId: plan.testCaseId,
        attempt: 0,
        timestamp: timestamp,
      ),
    ));
    for (final step in plan.steps) {
      _addStep(
        testCaseStartedId,
        step,
        _StepOutcome(messages.TestStepResultStatus.skipped),
        at,
        at,
      );
    }
    _add(messages.Envelope(
      testCaseFinished: messages.TestCaseFinished(
        testCaseStartedId: testCaseStartedId,
        timestamp: timestamp,
        willBeRetried: false,
      ),
    ));
  }

  void _addStep(
    String testCaseStartedId,
    _PlannedStep step,
    _StepOutcome outcome,
    DateTime startedAt,
    DateTime finishedAt,
  ) {
    final error = outcome.error;
    _add(messages.Envelope(
      testStepStarted: messages.TestStepStarted(
        testCaseStartedId: testCaseStartedId,
        testStepId: step.testStepId,
        timestamp: messages.dateTimeToTimestamp(startedAt),
      ),
    ));
    _add(messages.Envelope(
      testStepFinished: messages.TestStepFinished(
        testCaseStartedId: testCaseStartedId,
        testStepId: step.testStepId,
        timestamp: messages.dateTimeToTimestamp(finishedAt),
        testStepResult: messages.TestStepResult(
          status: outcome.status,
          duration: messages.durationToDurationMessage(outcome.duration),
          message: outcome.message,
          exception: (error == null)
              ? null
              : messages.Exception(
                  type: error.runtimeType.toString(),
                  message: error.toString(),
                  // Like in other Cucumber implementations, the stack trace
                  // starts with the error, since tools may show only this.
                  stackTrace: outcome.message,
                ),
        ),
      ),
    ));
  }

  /// The result of [step] in [execution]. A step fails if one of its code
  /// blocks failed or didn't finish, passes if all of them passed, and is
  /// skipped if they didn't run. A step with no code passes, unless a step
  /// before it failed.
  _StepOutcome _outcomeOf(
    _PlannedStep step,
    BddExecution execution, {
    required bool failedBefore,
  }) {
    final results = step.isHook
        ? [...execution.callbackResults, ..._resultsOf(step, execution)]
        : _resultsOf(step, execution).toList();

    if (results.isEmpty) {
      final hasCode = step.isHook || step.codeTerms.isNotEmpty;
      return _StepOutcome(
        (failedBefore || hasCode)
            ? messages.TestStepResultStatus.skipped
            : messages.TestStepResultStatus.passed,
      );
    }

    final duration = results.fold(
      Duration.zero,
      (total, result) => total + (result.duration ?? Duration.zero),
    );
    final startedAt = results.first.startedAt;

    final failure = results.firstWhereOrNull((result) => !result.passed);
    if (failure != null) {
      final error = failure.error;
      return _StepOutcome(
        messages.TestStepResultStatus.failed,
        duration: duration,
        startedAt: startedAt,
        error: error,
        stackTrace: failure.stackTrace,
        message: (error == null)
            ? 'The step did not finish. It may have timed out.'
            : '$error\n${failure.stackTrace ?? ''}'.trimRight(),
      );
    }

    final allRan = step.isHook ||
        step.codeTerms.every((code) => execution.resultOf(code) != null);
    return allRan
        ? _StepOutcome(
            messages.TestStepResultStatus.passed,
            duration: duration,
            startedAt: startedAt,
          )
        : _StepOutcome(messages.TestStepResultStatus.skipped);
  }

  Iterable<BddCodeExecution> _resultsOf(
    _PlannedStep step,
    BddExecution execution,
  ) =>
      step.codeTerms.map(execution.resultOf).nonNulls;
}

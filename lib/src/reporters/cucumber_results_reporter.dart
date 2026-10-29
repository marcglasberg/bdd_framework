import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:collection/collection.dart';
import 'package:cucumber_gherkin/cucumber_gherkin.dart' as gherkin;
import 'package:cucumber_messages/cucumber_messages.dart' as messages;

import '../core.dart';

/// Writes the results of your BDDs (which scenarios and steps passed, failed
/// or were skipped, how long they took, and the errors) in Cucumber's standard
/// results format, so that tools made for Cucumber can show and use them.
///
/// The format is called
/// [Cucumber Messages](https://github.com/cucumber/messages): an NDJSON file,
/// with one JSON message per line.
///
/// ## Who should use it, and why
///
/// Use it when you need the results of your BDDs outside your IDE and console.
/// For example:
///
/// * To create an **HTML report** of each test run, with every scenario, its
///   steps, and what passed or failed. You can publish it from CI, or share it
///   with people who don't read code, like product owners and QA. See
///   "HTML report" below.
///
/// * To send the results to other **tools that understand Cucumber**. Cucumber
///   provides converters from this format to JUnit XML, which most CI systems
///   show as test results, and to the older Cucumber JSON format, which some
///   CI plugins and Jira test-management apps import.
///
/// You don't need it to see results while you work: [ConsoleReporter] already
/// does that. And to keep your BDDs as living documentation, or to show them
/// in Jira, use [FeatureFileReporter], which writes the `.feature` files. In
/// short, the [FeatureFileReporter] writes what your BDDs **specify**, and the
/// [CucumberResultsReporter] writes what happened when they **ran**. Both can
/// be used together.
///
/// The results file contains the same Gherkin the [FeatureFileReporter]
/// writes, so tools show the results next to your scenarios.
///
/// ## Usage
///
/// The default final path is `./gen_cucumber_results/results.ndjson`. Use the
/// [path] parameter to choose another file. Using an environment variable lets
/// each run use its own directory (with `dart:io` imported):
///
/// ```dart
/// void main() async {
///   final directory = Platform.environment['BDD_REPORT_DIR']!;
///   BddReporter.set(
///     CucumberResultsReporter(path: '$directory/results.ndjson'),
///   );
///   group('bdd_buy_and_sell.dart', bdd_buy_and_sell.main);
///   await BddReporter.reportAll();
/// }
/// ```
///
/// The report is created in two steps:
///
/// 1. While the tests run, [report] writes `path.partial`. It has everything
///    except the final `testRunFinished` message, because the result of the
///    whole run is only known after the test process exits.
///
/// 2. After the test process exits, `dart run bdd_framework:finalize_cucumber_results`
///    reads the partial, the test runner's JSON output and its exit code, and
///    writes [path] with the result of the whole run. The equivalent API is
///    `finalizeCucumberResults()` in `package:bdd_framework/cucumber_results.dart`.
///
/// Run the tests with a dedicated JSON file reporter (`--file-reporter`), not
/// with redirected console output. The normal console output is still shown.
/// In PowerShell:
///
/// ```powershell
/// $env:BDD_REPORT_DIR = Join-Path $PWD "gen_cucumber_results/run-$([Guid]::NewGuid())"
/// New-Item -ItemType Directory -Path $env:BDD_REPORT_DIR -ErrorAction Stop | Out-Null
/// flutter test test/bdd_test.dart "--file-reporter=json:$env:BDD_REPORT_DIR/runner.json"
/// $testExit = $LASTEXITCODE
/// dart run bdd_framework:finalize_cucumber_results "--results=$env:BDD_REPORT_DIR/results.ndjson" "--runner-json=$env:BDD_REPORT_DIR/runner.json" "--exit-code=$testExit"
/// $finalizeExit = $LASTEXITCODE
/// if ($testExit -ne 0) { exit $testExit }
/// exit $finalizeExit
/// ```
///
/// Or in a POSIX shell:
///
/// ```sh
/// mkdir -p gen_cucumber_results || exit 2
/// BDD_REPORT_DIR=$(mktemp -d "$PWD/gen_cucumber_results/run.XXXXXXXX") || exit 2
/// export BDD_REPORT_DIR
/// test_status=0
/// flutter test test/bdd_test.dart --file-reporter="json:$BDD_REPORT_DIR/runner.json" || test_status=$?
/// finalize_status=0
/// dart run bdd_framework:finalize_cucumber_results --results="$BDD_REPORT_DIR/results.ndjson" --runner-json="$BDD_REPORT_DIR/runner.json" --exit-code="$test_status" || finalize_status=$?
/// if [ "$test_status" -ne 0 ]; then exit "$test_status"; fi
/// exit "$finalize_status"
/// ```
///
/// Here, `test/bdd_test.dart` is the entry point that collects the BDDs for
/// this report. For Dart tests, replace `flutter test` with `dart test`.
///
/// * Always run the finalizer after the tests, even when they fail. Don't
///   chain the two commands with `&&`.
/// * The finalizer exits with 0 for success, 1 for a confirmed test failure,
///   or 2 for an incomplete, unsupported or inconsistent run, or an export
///   error. It never starts other processes.
/// * Use a new directory for each run. If several test entry points each set
///   up a reporter, give each its own directory, instead of having them all
///   write the same file.
/// * IDE runs, which don't use the JSON file reporter, only produce the
///   partial file. Use the two commands when you need a complete report.
///
/// ## How BDD results become Cucumber results
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
///   an `After` hook named `run() callback`. Cucumber tools usually hide hooks
///   that pass, but a hook that fails fails the test case and shows the error.
///   So, to see which step failed, put the step's code in `.code()`.
///
/// * A BDD that was skipped, or that didn't run (for example, because of
///   `.only`), is reported with all its steps skipped.
///
/// * The step details describe what happened inside the BDDs. Setup/teardown
///   failures and timeouts can happen outside of them. That's why the global
///   result (`testRunFinished.success`) comes from the test runner, through
///   the finalizer, and not from the steps. It covers the whole test command,
///   including tests that are not BDDs. So a failure outside a BDD step can
///   appear next to steps that all passed: the finalizer doesn't invent a
///   failing step. Retries that eventually pass correctly give a global
///   success. An interrupted or unverifiable run gives an error and no final
///   report, never a fake failure or success.
///
/// * Example values are inserted once, from the original text. For example,
///   `<a>` with `a = '<b><b>'` stays the literal `<b><b>`, even if there is a
///   `b` column.
///
/// ## Errors
///
/// Invalid Gherkin, scenarios/steps/examples that don't match the BDDs,
/// serialization errors and output failures make [report] throw, and
/// `BddReporter.reportAll()` passes that error on through its teardown. No BDD
/// is silently left out.
///
/// An existing report at [path] is deleted before a new one is created, so a
/// failed run never leaves an old report that looks current. If it can't be
/// deleted (for example, because of permissions), the export stops. Never use
/// or upload a file left at the path after an error. The report is written to
/// a temporary file in the same directory, and only then renamed into place,
/// so a half-written report is never published.
///
/// ## Where to save the report
///
/// Put the report in a private directory that no other user or process can
/// change while the report is written. Links in the report path, or in its
/// parent directories, are rejected, and the reporter won't overwrite a file
/// that appears at the destination while it works. Still, portable Dart file
/// APIs can't fully protect against someone changing the directories at the
/// same time.
///
/// If a trusted system directory is itself a link, such as `/var` on macOS,
/// resolve it with `Directory.resolveSymbolicLinks()` before choosing the
/// report path.
///
/// Use a new private directory for each command, and a separate path for each
/// reporter or test process. Two runs that write the same path make the
/// finalizer fail. Don't upload a partial file, or a file left after an error.
/// A report of a confirmed test failure is still useful to find the problem,
/// but must not make CI pass.
///
/// ## Sensitive data
///
/// Treat the NDJSON file, and any HTML made from it, as sensitive. They
/// contain scenario text, example and table values, error messages, stack
/// traces and platform versions. Don't put real passwords or personal data in
/// test descriptions or in thrown errors, and replace sensitive values before
/// they reach the BDD. Nothing detects or removes secrets automatically. Limit
/// who can access the reports and how long they are kept, and check them
/// before sharing.
///
/// ## HTML report
///
/// To turn the **finalized** file into HTML, use Cucumber's HTML formatter for
/// JavaScript. For example, after
/// `npm install --save-exact @cucumber/html-formatter @cucumber/message-streams`,
/// create a `render.mjs` file, and run it with `node render.mjs`:
///
/// ```js
/// import fs from 'node:fs'
/// import { pipeline } from 'node:stream/promises'
/// import { CucumberHtmlStream } from '@cucumber/html-formatter'
/// import { NdjsonToMessageStream } from '@cucumber/message-streams'
///
/// await pipeline(
///   fs.createReadStream(`${process.env.BDD_REPORT_DIR}/results.ndjson`, 'utf-8'),
///   new NdjsonToMessageStream(),
///   new CucumberHtmlStream(),
///   fs.createWriteStream('report.html', 'utf-8'),
/// )
/// ```
///
/// Keep the npm versions and lockfile under review, use `npm ci` for
/// repeatable installs, and watch for security updates of the formatter.
/// Opening an HTML report may load remote content placed in descriptions, such
/// as Markdown images. Open untrusted reports offline, or with restricted
/// network access, and don't embed reports in a privileged web app. This
/// reporter doesn't run the formatter, and never sends anything over the
/// network. But if you choose a path on a network drive, the file is of course
/// written there.
///
/// ## Size limits
///
/// Reports that are too large are rejected with an error, instead of using
/// unbounded memory:
///
/// * 1 Mi characters of Gherkin per feature.
/// * 16 Mi characters per report, counting the Gherkin and the text created by
///   inserting example values.
/// * 256 columns per `Examples` table.
/// * 100,000 compiled test cases, steps, table rows, cells and tags combined,
///   per report.
/// * 10,000 recorded runs and 100,000 messages per report.
/// * 64 MiB of UTF-8 per report file.
///
/// Split very large suites into separate reports. These limits only apply to
/// the report. They don't limit your test code, or custom `toString()` and
/// table formatting, which run before the reporter gets the text.
class CucumberResultsReporter extends BddReporter {
  /// Creates a reporter whose finalized Cucumber Messages will be at [path].
  /// The intermediate file is `path.partial`. Directories are created as needed.
  CucumberResultsReporter({this.path = './gen_cucumber_results/results.ndjson'});

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
      'Partial Cucumber results saved in $path.partial; '
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

// -------------------------------------------------------------------------
// Gherkin source of a feature.
// -------------------------------------------------------------------------

/// The Gherkin text of [feature], with its background and all its BDDs.
///
/// This is the content of the `.feature` file the [FeatureFileReporter]
/// writes, and the source the `CucumberResultsReporter` reports.
String gherkinSource(BddFeature feature, {int? maxLength}) {
  final result = StringBuffer();
  void append(Object value) {
    final text = value.toString();
    if (maxLength != null && result.length + text.length > maxLength) {
      throw StateError(
        'Gherkin source exceeded the $maxLength character limit.',
      );
    }
    result.write(text);
  }

  append(feature);

  if (feature.backgroundFramework != null) {
    append('\n');
    append(feature.background.toString());
  }

  for (final test in feature.testResults) {
    append('\n');
    for (final term in test.terms) {
      append(term.toString());
      append('\n');
    }
  }

  return result.toString();
}

// -------------------------------------------------------------------------
// Pickle compilation, with bounded example substitution.
// -------------------------------------------------------------------------

// Pickle compilation follows cucumber_gherkin 42.0.1, with bounded,
// single-pass interpolation instead of recursively replacing example values.
// https://github.com/cucumber/gherkin/tree/main/dart
//
// MIT License
// Copyright (c) 2017 Cucumber Ltd, Gaspar Nagy, Björn Rasmusson,
// Peter Sergeant, and contributors
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

const _maxSourceCharacters = 1024 * 1024;
const _maxExpandedCharacters = 16 * 1024 * 1024;
const _maxGeneratedItems = 100000;
const _maxExampleColumns = 256;

/// Parses Gherkin without the upstream recursive example substitution.
///
/// Each source has at most 1 Mi UTF-16 code units. The shared [budget] permits
/// 16 Mi code units of source plus emitted text and 100,000 generated cases,
/// steps, table rows/cells and tags combined. Omitting it creates a fresh budget.
/// Examples have at most 256 columns, bounding the matcher before
/// it is constructed. A limit or ambiguous table throws [FormatException]
/// before the next output allocation. Parser errors remain parse-error envelopes
/// for the reporter to reject along with other invalid Gherkin.
List<messages.Envelope> safeGherkinMessages(
  String source,
  String uri,
  String Function() idGenerator, {
  GherkinMessageBudget? budget,
}) {
  if (source.length > _maxSourceCharacters) {
    throw const FormatException(
      'Gherkin source exceeds the 1 Mi character limit.',
    );
  }
  final sharedBudget = budget ?? GherkinMessageBudget();
  // Source and AST retain descriptions/comments that do not occur in pickles.
  // Account for them cumulatively before parsing another feature.
  sharedBudget._consumeCharacters(source.length);
  final envelopes = gherkin.generateMessages(
    source,
    uri,
    gherkin.GherkinOptions(includePickles: false, idGenerator: idGenerator),
  );
  if (envelopes.any((envelope) => envelope.parseError != null))
    return envelopes;

  final documents = envelopes
      .map((envelope) => envelope.gherkinDocument)
      .whereType<messages.GherkinDocument>();
  final compiler = _PickleCompiler(uri, idGenerator, sharedBudget);
  for (final document in documents.toList()) {
    compiler.compile(document, envelopes);
  }
  return envelopes;
}

/// Internal report-wide budget shared by all feature compilations.
///
/// A failed compilation consumes its reservations; discard the report and use a
/// new budget for a new report instead of retrying with a partially used budget.
class GherkinMessageBudget {
  int _characters = 0;
  int _items = 0;

  void _consumeCharacters(int count) {
    if (count > _maxExpandedCharacters - _characters) {
      throw const FormatException(
        'Gherkin source and expanded text exceed the 16 Mi character limit.',
      );
    }
    _characters += count;
  }

  String _literal(String value) {
    _consumeCharacters(value.length);
    return value;
  }

  void _item() {
    if (_items >= _maxGeneratedItems) {
      throw const FormatException(
        'Gherkin exceeds the 100000 generated item limit.',
      );
    }
    _items++;
  }
}

/// Matches only complete, literal header tokens in the original string.
/// Longest tokens win at the same position; replacements are never rescanned.
class _ExampleTokens {
  _ExampleTokens(List<messages.TableCell> headers) : width = headers.length {
    if (width > _maxExampleColumns) {
      throw const FormatException('Examples exceeds the 256 column limit.');
    }
    for (var i = 0; i < headers.length; i++) {
      final token = '<${headers[i].value}>';
      if (_columnOf.containsKey(token)) {
        throw const FormatException(
          'Duplicate Examples column names are ambiguous.',
        );
      }
      _columnOf[token] = i;
    }
    final tokens = _columnOf.keys.toList()
      ..sort((a, b) {
        final byLength = b.length.compareTo(a.length);
        return byLength == 0 ? a.compareTo(b) : byLength;
      });
    _pattern = tokens.isEmpty
        ? null
        : RegExp(tokens.map(RegExp.escape).join('|'));
  }

  final int width;
  final Map<String, int> _columnOf = {};
  late final RegExp? _pattern;

  void validate(messages.TableRow row) {
    if (row.cells.length != width) {
      throw const FormatException(
        'Examples row width does not match its header.',
      );
    }
  }

  String render(
    String original,
    messages.TableRow row,
    GherkinMessageBudget budget,
  ) {
    final pattern = _pattern;
    if (pattern == null) return budget._literal(original);
    final buffer = StringBuffer();
    var position = 0;
    for (final match in pattern.allMatches(original)) {
      budget._consumeCharacters(match.start - position);
      buffer.write(original.substring(position, match.start));
      final replacement = row.cells[_columnOf[match.group(0)]!].value;
      budget._consumeCharacters(replacement.length);
      buffer.write(replacement);
      position = match.end;
    }
    budget._consumeCharacters(original.length - position);
    buffer.write(original.substring(position));
    return buffer.toString();
  }
}

class _PickleCompiler {
  _PickleCompiler(this.uri, this.idGenerator, this._budget);

  final String uri;
  final String Function() idGenerator;
  final GherkinMessageBudget _budget;

  void compile(
    messages.GherkinDocument document,
    List<messages.Envelope> output,
  ) {
    final feature = document.feature;
    if (feature == null) return;
    List<messages.Step> background = const [];
    for (final child in feature.children) {
      if (child.background != null) {
        background = child.background!.steps;
      } else if (child.scenario != null) {
        _scenario(
          child.scenario!,
          background,
          feature.tags,
          feature.language,
          output,
        );
      } else if (child.rule != null) {
        final rule = child.rule!;
        Iterable<messages.Step> ruleBackground = background;
        for (final ruleChild in rule.children) {
          if (ruleChild.background != null) {
            ruleBackground = background.followedBy(ruleChild.background!.steps);
          } else if (ruleChild.scenario != null) {
            _scenario(
              ruleChild.scenario!,
              ruleBackground,
              feature.tags.followedBy(rule.tags),
              feature.language,
              output,
            );
          } else {
            throw const FormatException('Unsupported Gherkin rule child.');
          }
        }
      } else {
        throw const FormatException('Unsupported Gherkin feature child.');
      }
    }
  }

  void _scenario(
    messages.Scenario scenario,
    Iterable<messages.Step> background,
    Iterable<messages.Tag> inheritedTags,
    String language,
    List<messages.Envelope> output,
  ) {
    final tags = inheritedTags.followedBy(scenario.tags);
    if (scenario.examples.isEmpty) {
      _case(scenario, background, tags, language, output);
      return;
    }
    for (final examples in scenario.examples) {
      final header = examples.tableHeader;
      if (header == null) {
        if (examples.tableBody.isNotEmpty) {
          throw const FormatException('Examples rows require a header.');
        }
        continue; // An empty Examples section defines no cases.
      }
      final tokens = _ExampleTokens(header.cells);
      for (final row in examples.tableBody) {
        tokens.validate(row);
        _case(
          scenario,
          background,
          tags.followedBy(examples.tags),
          language,
          output,
          tokens: tokens,
          row: row,
        );
      }
    }
  }

  void _case(
    messages.Scenario scenario,
    Iterable<messages.Step> background,
    Iterable<messages.Tag> tags,
    String language,
    List<messages.Envelope> output, {
    _ExampleTokens? tokens,
    messages.TableRow? row,
  }) {
    _budget._item(); // Reserve the case before constructing its children.
    final steps = <messages.PickleStep>[];
    var keyword = messages.StepKeywordType.unknown;
    if (scenario.steps.isNotEmpty) {
      for (final step in background) {
        keyword = _keyword(step, keyword);
        steps.add(_step(step, keyword));
      }
    }
    for (final step in scenario.steps) {
      keyword = _keyword(step, keyword);
      steps.add(_step(step, keyword, tokens: tokens, row: row));
    }
    final pickleTags = <messages.PickleTag>[];
    for (final tag in tags) {
      _budget._item();
      pickleTags.add(
        messages.PickleTag(name: _budget._literal(tag.name), astNodeId: tag.id),
      );
    }
    output.add(
      messages.Envelope(
        pickle: messages.Pickle(
          id: idGenerator(),
          uri: _budget._literal(uri),
          location: row?.location ?? scenario.location,
          name: _text(scenario.name, tokens, row),
          language: _budget._literal(language),
          steps: steps,
          tags: pickleTags,
          astNodeIds: [scenario.id, if (row != null) row.id],
        ),
      ),
    );
  }

  messages.StepKeywordType _keyword(
    messages.Step step,
    messages.StepKeywordType previous,
  ) =>
      step.keywordType == null ||
          step.keywordType == messages.StepKeywordType.conjunction
      ? previous
      : step.keywordType!;

  String _text(String value, _ExampleTokens? tokens, messages.TableRow? row) =>
      tokens == null || row == null
      ? _budget._literal(value)
      : tokens.render(value, row, _budget);

  messages.PickleStep _step(
    messages.Step step,
    messages.StepKeywordType keyword, {
    _ExampleTokens? tokens,
    messages.TableRow? row,
  }) {
    _budget._item();
    final table = step.dataTable;
    final doc = step.docString;
    final both = table != null && doc != null;
    final tableFirst = both && table.location.line < doc.location.line;
    messages.PickleTable? pickleTable;
    if (table != null) {
      final rows = <messages.PickleTableRow>[];
      for (final tableRow in table.rows) {
        _budget._item();
        final cells = <messages.PickleTableCell>[];
        for (final cell in tableRow.cells) {
          _budget._item();
          cells.add(
            messages.PickleTableCell(value: _text(cell.value, tokens, row)),
          );
        }
        rows.add(messages.PickleTableRow(cells: cells));
      }
      pickleTable = messages.PickleTable(
        argumentIndex: both ? (tableFirst ? 1 : 2) : null,
        rows: rows,
      );
    }
    final pickleDoc = doc == null
        ? null
        : messages.PickleDocString(
            argumentIndex: both ? (tableFirst ? 2 : 1) : null,
            mediaType: doc.mediaType == null
                ? null
                : _text(doc.mediaType!, tokens, row),
            content: _text(doc.content, tokens, row),
          );
    final type = switch (keyword) {
      messages.StepKeywordType.context => messages.PickleStepType.context,
      messages.StepKeywordType.action => messages.PickleStepType.action,
      messages.StepKeywordType.outcome => messages.PickleStepType.outcome,
      messages.StepKeywordType.unknown => messages.PickleStepType.unknown,
      messages.StepKeywordType.conjunction => null,
    };
    return messages.PickleStep(
      id: idGenerator(),
      text: _text(step.text, tokens, row),
      type: type,
      astNodeIds: [step.id, if (row != null) row.id],
      argument: pickleTable == null && pickleDoc == null
          ? null
          : messages.PickleStepArgument(
              dataTable: pickleTable,
              docString: pickleDoc,
            ),
    );
  }
}

// -------------------------------------------------------------------------
// Finalization, after the test process exits.
// -------------------------------------------------------------------------

/// Publishes the final [CucumberResultsReporter] report at [path], using the
/// actual result of a completed test process. This is what the
/// `dart run bdd_framework:finalize_cucumber_results` command calls. See
/// [CucumberResultsReporter] for how to run both steps.
///
/// The test process must have used `--file-reporter=json:<runnerJsonPath>`.
/// Call this only after it exits, passing its unchanged [testExitCode].
///
/// Returns true for a confirmed success, and false for a confirmed test
/// failure. Missing, interrupted, inconsistent or unsupported results throw,
/// and leave no final report. The global result covers every test selected by
/// the command, including tests that are not BDDs.
///
/// What is checked:
///
/// * The partial at `path.partial` has a random run ID, which the reporter
///   also prints into the runner's JSON output. The run ID and the output path
///   must match in both files.
/// * The runner's JSON output must have exactly one `start` event, and end
///   with a conclusive `done` event that agrees with [testExitCode].
/// * The test cases and steps in the partial must reference each other
///   correctly.
/// * Only the public JSON protocol 0.1.x and the normal exit codes 0 and 1 are
///   supported. Other exit codes, cancellations, missing events and
///   contradictions leave the result incomplete, instead of guessing.
/// * The partial and the runner's JSON output are read up to 64 MiB each, and
///   the runner's JSON output up to 1,000,000 events.
///
/// The partial is consumed, even when validation fails, so finalizing again
/// requires running the tests again.
///
/// This prevents accidentally mixing runs, or reusing the same partial. It
/// does not authenticate the local files or the exit code your script passes,
/// and can't stop someone from restoring copies of both matching files. Keep
/// these inputs trusted, pass the actual exit code unchanged, and don't reuse
/// directories. If the test process fails before the reporter runs, a new
/// directory also prevents an older report from looking current.
///
/// Use one reporter per output path, and a new private directory per command.
/// Don't run two finalizers on the same path at the same time. Links in the
/// paths are rejected, but the parent directories must not be changed while
/// this runs.
Future<bool> finalizeCucumberResults({
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

// -------------------------------------------------------------------------
// Reading the test runner's JSON file reporter output.
// -------------------------------------------------------------------------

const _markerPrefix = 'bdd_framework.messages.v1:';
const _maximumBytes = 64 * 1024 * 1024;
const _maximumEvents = 1000000;
final _noncePattern = RegExp(r'^[0-9a-fA-F]{64}$');
final _protocolPattern = RegExp(r'^0\.1\.(?:0|[1-9][0-9]*)$');

/// Reads the dedicated JSON file reporter from one completed test-runner run.
///
/// [outputUri] is the canonical absolute file URI supplied by the caller (with
/// Windows case normalization already applied). This function performs no IO.
/// Only a coherent final `done.success` determines the result: earlier errors
/// may belong to failed attempts that were subsequently retried successfully.
/// Missing, malformed, ambiguous or inconsistent evidence throws rather than
/// guessing a result. Unknown event types with a valid base shape are allowed
/// for additive protocol compatibility.
bool readMessagesRunnerResult(
  String jsonLines, {
  required String runId,
  required String outputUri,
  required int testExitCode,
}) {
  if (!_validNonce(runId) || !_isOutputUri(outputUri)) {
    throw const FormatException('Invalid expected Messages run identity.');
  }
  if (testExitCode != 0 && testExitCode != 1) {
    throw const FormatException('Unsupported test-runner exit code.');
  }
  _checkBounds(jsonLines);

  final knownTests = <int>{};
  var started = false;
  bool? success;
  var outputMarkers = 0;
  var expectedMarker = false;

  for (final line in _lines(jsonLines)) {
    if (success != null) {
      throw const FormatException(
        'An event follows the final runner done event.',
      );
    }
    final event = _object(line, 'Invalid runner JSON event.');
    final type = event['type'];
    if (type is! String || type.isEmpty || !_nonnegativeInt(event['time'])) {
      throw const FormatException('Invalid runner event type or time.');
    }
    if (!started && type != 'start') {
      throw const FormatException('The first runner event must be start.');
    }

    switch (type) {
      case 'start':
        final version = event['protocolVersion'];
        if (started ||
            version is! String ||
            _protocolPattern.stringMatch(version) != version) {
          throw const FormatException(
            'Duplicate start or unsupported runner protocol.',
          );
        }
        started = true;
      case 'testStart':
        final test = event['test'];
        if (test is! Map<String, dynamic> || !_nonnegativeInt(test['id'])) {
          throw const FormatException('Invalid runner testStart identity.');
        }
        if (!knownTests.add(test['id'] as int)) {
          throw const FormatException('Duplicate runner test identity.');
        }
      case 'print':
        _knownTest(event['testID'], knownTests);
        final messageType = event['messageType'];
        final message = event['message'];
        if (messageType is! String ||
            messageType.isEmpty ||
            message is! String) {
          throw const FormatException('Invalid captured runner print event.');
        }
        if (messageType != 'print' || !message.startsWith(_markerPrefix)) {
          continue;
        }
        final marker = _object(
          message.substring(_markerPrefix.length),
          'Invalid Messages run marker.',
        );
        final markerId = marker['id'];
        final markerOutput = marker['output'];
        if (marker.length != 2 ||
            markerId is! String ||
            !_validNonce(markerId) ||
            markerOutput is! String ||
            !_isOutputUri(markerOutput)) {
          throw const FormatException('Invalid Messages run marker identity.');
        }
        if (markerOutput == outputUri) {
          outputMarkers++;
          if (outputMarkers > 1) {
            throw const FormatException(
              'Multiple Messages runs target the same output.',
            );
          }
          expectedMarker = markerId == runId;
        }
      case 'error':
        _knownTest(event['testID'], knownTests);
        if (event['error'] is! String ||
            event['stackTrace'] is! String ||
            event['isFailure'] is! bool) {
          throw const FormatException('Invalid runner error event.');
        }
      case 'testDone':
        _knownTest(event['testID'], knownTests);
        if (!const ['success', 'failure', 'error'].contains(event['result']) ||
            event['hidden'] is! bool ||
            event['skipped'] is! bool) {
          throw const FormatException('Invalid runner testDone event.');
        }
      case 'done':
        final completed = event['success'];
        if (completed is! bool) {
          throw const FormatException(
            'The test runner did not finish conclusively.',
          );
        }
        success = completed;
      default:
        // A marker is accepted only as a captured print from a known test.
        final message = event['message'];
        if (message is String && message.startsWith(_markerPrefix)) {
          throw const FormatException(
            'Messages marker is not a captured print event.',
          );
        }
    }
  }

  if (!started || success == null) {
    throw const FormatException('Incomplete test-runner JSON file.');
  }
  if (outputMarkers != 1 || !expectedMarker) {
    throw const FormatException('Missing expected Messages run marker.');
  }
  if (testExitCode != (success ? 0 : 1)) {
    throw const FormatException(
      'Runner done result disagrees with the exit code.',
    );
  }
  return success;
}

bool _nonnegativeInt(Object? value) => value is int && value >= 0;

bool _validNonce(String value) =>
    value.length == 64 && _noncePattern.hasMatch(value);

void _knownTest(Object? value, Set<int> knownTests) {
  if (!_nonnegativeInt(value) || !knownTests.contains(value)) {
    throw const FormatException('Runner event references an unknown test.');
  }
}

bool _isOutputUri(String value) {
  final uri = Uri.tryParse(value);
  return uri != null &&
      uri.scheme == 'file' &&
      uri.hasAbsolutePath &&
      !uri.hasQuery &&
      !uri.hasFragment &&
      uri.userInfo.isEmpty &&
      !uri.hasPort &&
      uri.normalizePath().path == uri.path;
}

Map<String, dynamic> _object(String line, String error) {
  try {
    final value = jsonDecode(line);
    if (value is Map<String, dynamic>) return value;
  } on FormatException {
    // Do not expose the JSON contents, which can contain test data or secrets.
  }
  throw FormatException(error);
}

/// Counts UTF-8 bytes without allocating a second, potentially larger copy.
/// Each NDJSON line is one event; check the event budget before decoding any.
void _checkBounds(String input) {
  if (input.isEmpty || input.length > _maximumBytes) {
    throw const FormatException('Runner JSON file is empty or exceeds 64 MiB.');
  }
  var bytes = 0;
  var lines = 0;
  for (var i = 0; i < input.length; i++) {
    final unit = input.codeUnitAt(i);
    if (unit == 10 && ++lines > _maximumEvents) {
      throw const FormatException('Runner JSON file exceeds 1000000 events.');
    }
    if (unit < 0x80) {
      bytes++;
    } else if (unit < 0x800) {
      bytes += 2;
    } else if (unit >= 0xd800 &&
        unit <= 0xdbff &&
        i + 1 < input.length &&
        input.codeUnitAt(i + 1) >= 0xdc00 &&
        input.codeUnitAt(i + 1) <= 0xdfff) {
      bytes += 4;
      i++;
    } else {
      bytes += 3;
    }
    if (bytes > _maximumBytes) {
      throw const FormatException('Runner JSON file exceeds 64 MiB.');
    }
  }
  if (!input.endsWith('\n') && ++lines > _maximumEvents) {
    throw const FormatException('Runner JSON file exceeds 1000000 events.');
  }
}

/// Accept LF or CRLF, including a complete final JSON record without a newline.
/// Blank lines and bare CR separators are not valid dedicated reporter output.
Iterable<String> _lines(String input) sync* {
  var start = 0;
  while (start < input.length) {
    final newline = input.indexOf('\n', start);
    var end = newline < 0 ? input.length : newline;
    if (newline >= 0 && end > start && input.codeUnitAt(end - 1) == 13) end--;
    final line = input.substring(start, end);
    if (line.trim().isEmpty || line.contains('\r')) {
      throw const FormatException('Invalid runner NDJSON line.');
    }
    yield line;
    start = newline < 0 ? input.length : newline + 1;
  }
}

// -------------------------------------------------------------------------
// Safe reading and writing of report files.
// -------------------------------------------------------------------------

/// Maximum encoded report size, including the newline after every envelope.
/// This helper is internal to the reporters and is not exported by the package.
const maxMessagesFileBytes = 64 * 1024 * 1024;

/// Invalidates an earlier report after checking the destination and ancestors.
/// Links and special files are never removed through this operation.
Future<void> invalidateMessagesFile(String path) async {
  _validatePath(path);
  final file = File(path).absolute;
  await _checkParents(file.parent, create: true);
  final type = await _destinationType(file);
  if (type == FileSystemEntityType.file) await file.delete();
}

/// Reads strict UTF-8 from a regular file, bounded even if the file grows.
/// The file and its parent directories must remain trusted and unchanged while
/// being read; portable dart:io cannot make path checks and open atomic.
Future<String> readMessagesFile(String path) async {
  _validatePath(path);
  final file = File(path).absolute;
  await _requireRegularFile(file);
  final input = await file.open();
  String? result;
  Object? failure;
  StackTrace? failureStack;
  try {
    if (await input.length() > maxMessagesFileBytes) throw _sizeError();
    final text = StringBuffer();
    final decoder = const Utf8Decoder(
      allowMalformed: false,
    ).startChunkedConversion(StringConversionSink.fromStringSink(text));
    var bytesRead = 0;
    while (true) {
      final chunk = await input.read(64 * 1024);
      if (chunk.isEmpty) break;
      bytesRead += chunk.length;
      if (bytesRead > maxMessagesFileBytes) throw _sizeError();
      decoder.add(chunk);
    }
    decoder.close();
    result = text.toString();
  } catch (error, stackTrace) {
    failure = error;
    failureStack = stackTrace;
  }
  try {
    await input.close();
  } catch (error, stackTrace) {
    failure ??= error;
    failureStack ??= stackTrace;
  }
  if (failure != null) Error.throwWithStackTrace(failure, failureStack!);
  await _requireRegularFile(file);
  return result!;
}

/// Claims a partial report before reading it, so its path can be consumed once.
/// The claimed copy is removed even when reading or UTF-8 decoding fails. This
/// prevents reuse of the same file, not replay of a separately copied artifact.
/// As with writing, parent directories must be trusted during the operation.
Future<String> consumeMessagesFile(String path) async {
  _validatePath(path);
  final source = File(path).absolute;
  await _requireRegularFile(source);
  Directory? claimDirectory;
  File? claimedFile;
  String? result;
  Object? failure;
  StackTrace? failureStack;
  try {
    claimDirectory = await source.parent.createTemp('.bdd-messages-claimed-');
    claimedFile = File('${claimDirectory.path}/report.tmp');
    await source.rename(claimedFile.path);
    result = await readMessagesFile(claimedFile.path);
  } catch (error, stackTrace) {
    failure = error;
    failureStack = stackTrace;
  }
  try {
    if (claimDirectory != null && claimedFile != null) {
      await _removeTemporary(claimDirectory, claimedFile);
    }
  } catch (error, stackTrace) {
    failure ??= error;
    failureStack ??= stackTrace;
  }
  if (failure != null) Error.throwWithStackTrace(failure, failureStack!);
  return result!;
}

Future<void> _requireRegularFile(File file) async {
  await _checkParents(file.parent, create: false);
  if (await _destinationType(file) != FileSystemEntityType.file) {
    throw FileSystemException(
      'Expected an existing regular report file',
      file.path,
    );
  }
}

/// Publishes a complete UTF-8 report, or leaves no partially written report.
///
/// Existing regular output is invalidated before [lines] is called, so a failed
/// build cannot leave an old successful report behind. The replacement is
/// flushed and closed in the same filesystem before being renamed into place.
///
/// Output and ancestor links (including Windows junctions) are rejected. The
/// parent directories must nevertheless be trusted and must not be changed by
/// other processes during this operation: portable dart:io does not provide
/// directory handles and no-follow operations that would eliminate these races.
/// A cleanup error after the rename can leave a complete, published report.
Future<void> writeMessagesFile(
  String path,
  Iterable<String> Function() lines,
) async {
  _validatePath(path);
  final destination = File(path).absolute;
  await invalidateMessagesFile(destination.path);

  Directory? temporaryDirectory;
  File? temporaryFile;
  RandomAccessFile? output;
  Object? failure;
  StackTrace? failureStack;
  try {
    // createTemp reserves a unique directory; an existing link cannot be used
    // as the staging location. The directory is on the destination filesystem.
    temporaryDirectory = await destination.parent.createTemp('.bdd-messages-');
    temporaryFile = File('${temporaryDirectory.path}/report.tmp');
    await temporaryFile.create(exclusive: true);
    output = await temporaryFile.open(mode: FileMode.write);

    var bytesWritten = 0;
    for (final line in lines()) {
      final remaining = maxMessagesFileBytes - bytesWritten - 1;
      // UTF-8 needs at least as many bytes as UTF-16 code units. Check before
      // allocating the encoded line, then check its actual byte size as well.
      if (line.length > remaining) throw _sizeError();
      final bytes = utf8.encode(line);
      if (bytes.length > remaining) throw _sizeError();
      await output.writeFrom(bytes);
      await output.writeByte(10);
      bytesWritten += bytes.length + 1;
    }
    await output.flush();
    await output.close();
    output = null;

    await _checkParents(destination.parent, create: false);
    await _checkParents(temporaryDirectory, create: false);
    if (await _destinationType(temporaryFile) != FileSystemEntityType.file) {
      throw FileSystemException(
        'Temporary report file changed',
        temporaryFile.path,
      );
    }
    if (await _destinationType(destination) != FileSystemEntityType.notFound) {
      throw FileSystemException(
        'The report destination changed while the report was built',
        destination.path,
      );
    }
    await temporaryFile.rename(destination.path);
  } catch (error, stackTrace) {
    failure = error;
    failureStack = stackTrace;
  }

  try {
    await output?.close();
  } catch (error, stackTrace) {
    failure ??= error;
    failureStack ??= stackTrace;
  }
  try {
    if (temporaryDirectory != null && temporaryFile != null) {
      await _removeTemporary(temporaryDirectory, temporaryFile);
    }
  } catch (error, stackTrace) {
    failure ??= error;
    failureStack ??= stackTrace;
  }
  if (failure != null) Error.throwWithStackTrace(failure, failureStack!);
}

StateError _sizeError() => StateError(
  'Cucumber Messages exceed the $maxMessagesFileBytes byte output limit',
);

void _validatePath(String path) {
  final parts = path.split(Platform.isWindows ? RegExp(r'[/\\]') : '/');
  if (path.isEmpty ||
      parts.last.isEmpty ||
      parts.last == '.' ||
      parts.last == '..' ||
      path.contains('\x00')) {
    throw FileSystemException('Expected a regular report file path', path);
  }
  if (!Platform.isWindows) return;
  final windowsPath = path.replaceAll('/', '\\');
  if (windowsPath.startsWith(r'\\?\') ||
      windowsPath.startsWith(r'\\.\') ||
      RegExp(r'^[a-zA-Z]:[^/\\]').hasMatch(path)) {
    throw FileSystemException('Unsupported Windows report path', path);
  }
  final reserved = RegExp(
    r'^(con|prn|aux|nul|conin\$|conout\$|clock\$|com[1-9\u00b9\u00b2\u00b3]|lpt[1-9\u00b9\u00b2\u00b3])(?:\.|$)',
    caseSensitive: false,
  );
  for (final part in parts) {
    if (part.isEmpty ||
        part == '.' ||
        part == '..' ||
        RegExp(r'^[a-zA-Z]:$').hasMatch(part))
      continue;
    if (part.contains(':') ||
        part.endsWith('.') ||
        part.endsWith(' ') ||
        reserved.hasMatch(part)) {
      throw FileSystemException(
        'Ambiguous or special Windows report path',
        path,
      );
    }
  }
}

Future<void> _checkParents(Directory parent, {required bool create}) async {
  final ancestors = <Directory>[];
  var directory = parent;
  while (true) {
    ancestors.add(directory);
    // A UNC share is the filesystem root; its server name alone is not a
    // directory that dart:io can validate.
    if (Platform.isWindows) {
      final windowsPath = directory.path.replaceAll('/', '\\');
      if (windowsPath.startsWith(r'\\') &&
          windowsPath.split('\\').where((part) => part.isNotEmpty).length ==
              2) {
        break;
      }
    }
    final next = directory.parent;
    if (next.path == directory.path) break;
    directory = next;
  }
  // Do not normalize away '..': the preceding component can itself be a link.
  for (final ancestor in ancestors.reversed) {
    var type = FileSystemEntity.typeSync(ancestor.path, followLinks: false);
    if (type == FileSystemEntityType.notFound && create) {
      await ancestor.create();
      type = FileSystemEntity.typeSync(ancestor.path, followLinks: false);
    }
    if (type != FileSystemEntityType.directory) {
      throw FileSystemException(
        'Report parent must be a directory, not a link or special file',
        ancestor.path,
      );
    }
  }
}

Future<FileSystemEntityType> _destinationType(File file) async {
  final type = FileSystemEntity.typeSync(file.path, followLinks: false);
  if (type == FileSystemEntityType.file) return type;
  if (type == FileSystemEntityType.notFound) {
    // Some platforms report devices as notFound. Enumerating the checked
    // parent distinguishes a missing name from an existing special file;
    // errors listing the parent propagate instead of being treated as absence.
    final name = file.uri.pathSegments.last;
    await for (final entity in file.parent.list(followLinks: false)) {
      final entryName = entity.uri.pathSegments.where((s) => s.isNotEmpty).last;
      if (Platform.isWindows
          ? entryName.toLowerCase() == name.toLowerCase()
          : entryName == name) {
        throw FileSystemException(
          'Report destination is not a regular file',
          file.path,
        );
      }
    }
    return type;
  }
  throw FileSystemException(
    'Report destination must be a regular file, not a link or directory',
    file.path,
  );
}

Future<void> _removeTemporary(Directory directory, File file) async {
  await _checkParents(directory.parent, create: false);
  final directoryType = FileSystemEntity.typeSync(
    directory.path,
    followLinks: false,
  );
  if (directoryType == FileSystemEntityType.notFound) return;
  if (directoryType == FileSystemEntityType.link) {
    await Link(directory.path).delete();
    return;
  }
  if (directoryType != FileSystemEntityType.directory) {
    throw FileSystemException(
      'Temporary report directory changed',
      directory.path,
    );
  }
  final type = FileSystemEntity.typeSync(file.path, followLinks: false);
  if (type == FileSystemEntityType.file) {
    await file.delete();
  } else if (type == FileSystemEntityType.link) {
    await Link(file.path).delete();
  } else if (type != FileSystemEntityType.notFound) {
    throw FileSystemException('Temporary report file changed', file.path);
  }
  // Never recursively delete an unexpected entry or follow a substituted link.
  await directory.delete();
}

part of 'bdd_base.dart';

/// A function type that represents the signature of the underlying test delegate
/// (like `test` or `testWidgets`) injected into [BddRunner].
///
/// This allows the [BddRunner] to be decoupled from the specific testing framework,
/// as the actual testing logic is injected via this function.
typedef BddContextTransformer = BddContext Function(BddContext context);

typedef BddContextTransformationHandler = void Function(
  BddContextTransformer transformContext,
);

class TestInvocation {
  const TestInvocation({
    required this.description,
    required this.body,
    this.timeout,
    this.skip,
    this.tags,
    this.onPlatform,
    this.retry,
    this.testOn,
    this.transformContext,
  });

  final String description;
  final Future<void> Function() body;
  final Timeout? timeout;
  final bool? skip;
  final dynamic tags;
  final Map<String, dynamic>? onPlatform;
  final int? retry;
  final dynamic testOn;
  final BddContextTransformationHandler? transformContext;
}

typedef TestDelegate = void Function(TestInvocation invocation);

/// Orchestrates the execution of BDD tests by connecting BDD scenarios to the
/// underlying test framework via an injected [TestDelegate].
class BddRunner {
  /// Runs a BDD test by gathering its steps and executing them via the provided [testFn].
  ///
  /// * [bdd]: The [BddFramework] instance containing the test structure.
  /// * [code]: The [CodeRun] closure to be added as the final execution step.
  /// * [testFn]: The underlying test runner function (from `package:test` or `package:flutter_test`).
  /// * [errorHandler]: An optional callback to handle errors occurring during test execution.
  void run(
    BddFramework bdd,
    CodeRun code,
    TestDelegate testDelegate,
    void Function(Object error, StackTrace stackTrace)? errorHandler,
    [
    bool Function()? rethrowAfterHandling,
  ]
  ) {
    // Add the final implementation code to the BDD framework.
    bdd.addCode(code);

    // Register this BDD test with all active reporters.
    for (var reporter in BddReporter._reporters) {
      reporter._addBdd(bdd);
    }

    int numberOfExamples = bdd.numberOfExamples();
    BddReporter.runInfo.testCount++;

    // If there are no examples, run the scenario once.
    if (numberOfExamples == 0) {
      _runTheTest(
        bdd,
        null,
        testDelegate,
        errorHandler,
        rethrowAfterHandling,
      );
    } else {
      for (int i = 0; i < numberOfExamples; i++) {
        _runTheTest(
          bdd,
          i,
          testDelegate,
          errorHandler,
          rethrowAfterHandling,
        );
      }
    }
  }

  /// Default configuration used for the ANSI-colored console output during execution.
  static const BddConfig config = BddConfig(
    keywords: BddKeywords(
      feature: '${boldItalic}Feature:$boldItalicOff',
      scenario: '${boldItalic}Scenario:$boldItalicOff',
      scenarioOutline: '${boldItalic}Scenario Outline:$boldItalicOff',
      given: '${boldItalic}Given$boldItalicOff',
      when: '${boldItalic}When$boldItalicOff',
      then: '${boldItalic}Then$boldItalicOff',
      and: '${boldItalic}And$boldItalicOff',
      but: '${boldItalic}But$boldItalicOff',
      comment: '$boldItalic#$boldItalicOff',
      examples: '${boldItalic}Examples:$boldItalicOff',
    ),
    keywordPrefix: BddKeywords.only(
      scenario: '\n',
      scenarioOutline: '\n',
      comment: grey,
    ),
    suffix: BddKeywords.only(
      comment: blue,
    ),
  );

  /// Converts an integer into a subscript string (e.g., 1 -> ₁).
  /// Used for numbering multiple example runs.
  String subscript(int index) {
    String result = '';
    var x = index.toString();
    for (int i = 0; i < x.length; i++) {
      var char = x[i];
      result += {
        '0': '₀',
        '1': '₁',
        '2': '₂',
        '3': '₃',
        '4': '₄',
        '5': '₅',
        '6': '₆',
        '7': '₇',
        '8': '₈',
        '9': '₉'
      }[char]!;
    }
    return result;
  }

  /// Generates a string representing the test iteration, potentially with a subscript for examples.
  /// For example: "4" (no examples) or "4₁" (first example of test 4).
  String testCountStr(int testCount, int? exampleNumber) =>
      "$testCount${exampleNumber == null ? '' : subscript(exampleNumber + 1)}";

  /// Internal method to execute the BDD steps within the provided [testFn] wrapper.
  /// Handles retry logic, error reporting, and context initialization.
  void _runTheTest(
    BddFramework bdd,
    int? exampleNumber,
    TestDelegate testDelegate,
    void Function(Object error, StackTrace stackTrace)? errorHandler,
    bool Function()? rethrowAfterHandling,
  ) {
    BddReporter.runInfo.totalTestCount++;

    var totalRetries = bdd._config?.retry ?? 0;
    var currentExecution = 0;

    String bddStr = bdd.toString(config: config, withFeature: true);
    int testCount = BddReporter.runInfo.testCount;

    if (bdd._skip) BddReporter.runInfo.skipCount++;

    String _testCountStr = testCountStr(testCount, exampleNumber);

    final example = BddTableValues.from(bdd.exampleRow(exampleNumber));
    final tables = BddMultipleTableValues.from(bdd.tables());
    var ctx = BddContext(example, tables);

    testDelegate(
      TestInvocation(
        description: '$_testCountStr ${bdd.description()}',
        body: () async {
        currentExecution++;

        // Log the test start to console with ANSI colors.
        print((currentExecution == 1)
            ? "${_header(bdd._skip, _testCountStr)}$blue$bddStr$boldOff"
            : "\n${red}Retry $currentExecution.\n$boldOff");

        try {
          // 1) Execute background setups if present.
          BddFramework? backgroundOption = bdd.feature?.backgroundFramework;
          if (backgroundOption != null) {
            for (CodeRun codeRun in backgroundOption.codeTerms
                .map((BddCodeTerm codeTerm) => codeTerm.codeRun)) {
              await codeRun.call(ctx);
            }
          }

          // 2) Sequentially execute all code blocks registered for this BDD scenario.
          for (CodeRun codeRun in bdd.codeTerms
              .map((BddCodeTerm codeTerm) => codeTerm.codeRun)) {
            await codeRun.call(ctx);
          }

          for (CodeRun codeRun in bdd.codeRuns) {
            await codeRun.call(ctx);
          }
        } catch (error, stacktrace) {
          // Mark as failed and report.
          bdd.passed.add(false);
          BddReporter.runInfo.failedCount++;
          print("\n");

          if (errorHandler != null) {
            errorHandler(error, stacktrace);
          } else {
            print("Exception: $error\n$stacktrace");
          }

          print(_fail(_testCountStr));
          if (rethrowAfterHandling?.call() ?? false) {
            Error.throwWithStackTrace(
              TestFailure('Test failed. See exception logs above.'),
              stacktrace,
            );
          }
          return;
        }

        // Mark as passed.
        bdd.passed.add(true);
        BddReporter.runInfo.passedCount++;
        print(_footer(_testCountStr));
      },
        transformContext: (transformContext) =>
            ctx = transformContext(ctx),
        timeout: bdd._timeout != null ? Timeout(bdd._timeout!) : Timeout.none,
        skip: bdd._skip,
        tags: bdd._config?.tags,
        onPlatform: bdd._config?.onPlatform,
        retry: totalRetries,
        testOn: bdd._config?.testOn,
      ),
    );
  }

  // ANSI color constants and helpers for console formatting.
  static const red = "\x1B[38;5;9m";
  static const blue = "\x1B[38;5;45m";
  static const yellow = "\x1B[38;5;226m";
  static const grey = "\x1B[38;5;246m";
  static const bold = "\u001b[1m";
  static const italic = "\u001b[3m";
  static const boldItalic = bold + italic;
  static const boldItalicOff = boldOff + italicOff;
  static const boldOff = "\u001b[22m";
  static const italicOff = "\u001b[23m";
  static const reset = "\u001b[0m";

  String _header(bool skip, String testNumberStr) {
    return yellow +
        italic +
        "TEST $testNumberStr ${skip ? "SKIPPED" : ""} "
            "$italicOff══════════════════════════════════════════════════$reset\n\n";
  }

  String _footer(String testNumberStr) =>
      grey + "\n✔ ${italic}TEST $testNumberStr PASSED!\n\n" + italicOff;

  String _fail(String testNumberStr) =>
      grey + "\n⚠ ${italic}TEST $testNumberStr FAILED!\n" + italicOff;
}

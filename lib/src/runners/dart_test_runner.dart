import 'package:test/test.dart';

import '../core.dart';

/// Extension providing the standard `.run()` method for pure Dart BDD tests.
///
/// Use this entry point when you are writing tests for logic that does not depend on Flutter.
/// It wraps the execution within the standard `package:test` library's `test()` function.
extension DartTestRun on BddRunnable {
  /// Executes the BDD scenario as a standard Dart unit test.
  ///
  /// This method uses the [BddRunner] to orchestrate step execution and delegates the
  /// underlying test lifecycle management to `package:test`.
  /// Exceptions and failed assertions are recorded in the BDD report and also
  /// fail the underlying test, including errors from asynchronous steps.
  void run([CodeRun? testCallback]) {
    BddRunner().run(
      bdd,
      testCallback ?? (ctx) async {}, // Default empty CodeRun
      _testDelegate,
      null, // Print the original error and stack trace before failing the test.
      () => true,
    );
  }
}

/// Extension to attach Dart-specific executable closures (code blocks) to BDD terms.
///
/// By importing `bdd_dart.dart`, these extensions become available on steps like
/// [BddGiven], [BddWhen], and [BddThen], allowing you to define the logic for each step.
extension DartTestCode<T> on BddCodeable<T> {
  /// Attaches a code block that executes within a pure Dart [BddContext].
  ///
  /// The [codeRun] function receives a [BddContext] which provides access to
  /// values defined in Example tables.
  T code(CodeRun codeRun) {
    return addCode(codeRun);
  }
}

/// Internal helper that bridges the [BddRunner] to the pure Dart `test()` function.
void _testDelegate(TestInvocation invocation) {
  test(
    invocation.description,
    invocation.body,
    timeout: invocation.timeout,
    skip: invocation.skip,
    tags: invocation.tags,
    onPlatform: invocation.onPlatform,
    retry: invocation.retry,
    testOn: invocation.testOn,
  );
}

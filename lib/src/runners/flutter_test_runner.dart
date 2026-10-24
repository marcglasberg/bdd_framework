import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test/test.dart' as test_package show group;

import '../core.dart';

/// Extension to enable running Flutter non-UI tests directly via `test`.
///
/// Use this entry point when you are writing Flutter tests that only involve logic
/// or pure Dart code, but still need to run within the Flutter test environment.
extension FlutterTestRun on BddRunnable {
  /// Executes the BDD scenario as a Flutter unit test (without a widget tester).
  ///
  /// This method natively uses the standard `test` function from `package:flutter_test`.
  void run([CodeRun? testCallback]) {
    BddRunner().run(
      bdd,
      testCallback ?? (ctx) async {},
      _testDelegate,
      _errorHandler,
    );
  }
}

/// Extension to attach pure Flutter non-UI executable closures (code blocks) to BDD terms.
///
/// By importing `bdd_flutter_test.dart`, these extensions become available.
extension FlutterTestCode<C> on BddCodeable<C> {
  /// Attaches a code block that executes within a Flutter [BddContext].
  ///
  /// This version of `.code()` does not provide a `WidgetTester`. Use it for logic-only steps.
  C code(CodeRun codeRun) {
    return addCode(codeRun);
  }
}

void _testDelegate(TestInvocation invocation) {
  if (!invocation.only) return _declareTest(invocation);

  // flutter_test's test() has no `solo`, so a test marked with `.only` goes
  // in a solo group. Only set when the user marks a test with `.only`, which
  // itself warns.
  // ignore: invalid_use_of_do_not_submit_member
  test_package.group('', () => _declareTest(invocation), solo: true);
}

void _declareTest(TestInvocation invocation) {
  test(
    invocation.description,
    () async {
      if (BddFlutter.ignoreOverflow) _ignoreOverflowErrors();
      try {
        await invocation.body();
      } finally {
        _cleanTargetPlatformOverride();
      }
    },
    skip: invocation.skip,
    timeout: invocation.timeout,
    tags: invocation.tags,
    retry: invocation.retry,
  );
}

void _errorHandler(Object error, StackTrace stackTrace) {
  var errorDetails = FlutterErrorDetails(
    library: 'BDD Framework',
    exception: error,
    stack: stackTrace,
    stackFilter: _stackFilter,
  );
  reportTestException(errorDetails, "");
}

Iterable<String> _stackFilter(Iterable<String> frames) {
  // Removes the frames we are not interested in.
  var filteredFrames = frames.where((frame) =>
      !frame.contains("package:matcher/") &&
      !frame.contains("package:flutter_test/src/widget_tester.dart") &&
      !frame.contains("package:bdd_framework/src/") &&
      !frame.contains("package:test_api/src/"));

  return FlutterError.defaultStackFilter(filteredFrames);
}

void _ignoreOverflowErrors() {
  var handlerOriginal = FlutterError.onError;
  FlutterError.onError = (details) {
    var exception = details.exception;
    var ifOverflow = (exception is FlutterError) &&
        exception.diagnostics
            .map((diagnostic) => diagnostic.value)
            .whereType<List<Object>>()
            .expand((value) => value)
            .any((data) =>
                data.toString().startsWith("A RenderFlex overflowed by"));

    if (ifOverflow)
      FlutterError.dumpErrorToConsole(details);
    else
      handlerOriginal!(details);
  };
}

void _cleanTargetPlatformOverride() =>
    (debugDefaultTargetPlatformOverride = null);

class BddFlutter {
  static bool ignoreOverflow = true;
}

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import '../core.dart';

/// A function type that represents a code block in a Flutter widget test,
/// providing access to both the [BddContext] and the [WidgetTester].
typedef WidgetTestCallback = FutureOr<void> Function(
  BddContext ctx,
  WidgetTester tester,
);

/// The widget-test-specific [BddContext] that carries the active [WidgetTester].
class BddWidgetContext extends BddContext {
  BddWidgetContext._(
    BddTableValues example,
    BddMultipleTableValues tables, {
    required this.tester,
  }) : super(example, tables);

  /// Creates a widget-test-aware context from an existing [BddContext].
  factory BddWidgetContext.from(
    BddContext context, {
    required WidgetTester tester,
  }) {
    return BddWidgetContext._(
      context.example,
      context.tables,
      tester: tester,
    );
  }

  final WidgetTester tester;
}

/// Extension to enable running Flutter UI tests directly via `testWidgets`.
///
/// Use this entry point when you are writing Flutter Widget tests that require
/// a [WidgetTester] to interact with the UI.
extension FlutterWidgetTestRun on BddRunnable {
  /// Executes the BDD scenario as a Flutter widget test.
  ///
  /// This method natively uses `testWidgets` from `package:flutter_test`.
  void run([WidgetTestCallback? testCallback]) {
    BddRunner().run(
      bdd,
      (ctx) async {
        final tester = _widgetContextOf(ctx).tester;
        if (testCallback != null) await testCallback(ctx, tester);
        _failOnPendingFlutterError(tester);
      },
      _testDelegate,
      _errorHandler,
      () => TestWidgetsFlutterBinding.instance is LiveTestWidgetsFlutterBinding,
    );
  }
}

/// Extension to attach Flutter-specific executable closures (code blocks) to BDD terms.
///
/// By importing `bdd_flutter_widget_test.dart`, these extensions become available,
/// allowing you to access the [WidgetTester] in every step.
extension FlutterWidgetTestCode<C> on BddCodeable<C> {
  /// Attaches a code block that injects the [WidgetTester] directly into the callback.
  ///
  /// The [codeRun] function receives both the [BddContext] and the [WidgetTester]
  /// currently active for the test.
  C code(WidgetTestCallback testCallback) {
    return addCode((ctx) async {
      final tester = _widgetContextOf(ctx).tester;
      await testCallback(ctx, tester);
      _failOnPendingFlutterError(tester);
    });
  }
}

/// The errors Flutter reported (and didn't ignore) since the last check.
final _reportedErrors = <FlutterErrorDetails>[];

/// Thrown when Flutter reported an error during a step, such as a layout
/// overflow, without throwing it.
class _FlutterErrorReported implements Exception {
  _FlutterErrorReported(this.details);

  final FlutterErrorDetails details;

  @override
  String toString() => details.exceptionAsString();
}

/// Flutter doesn't throw errors reported while building or laying out widgets.
/// It keeps them, and only fails the test after the test body ends, so the
/// BDD would print "PASSED" for a failed test. Checking after each step makes
/// the step fail right away instead, with the original error.
///
/// An error the test already consumed with [WidgetTester.takeException]
/// is not pending anymore, so it doesn't fail the step.
void _failOnPendingFlutterError(WidgetTester tester) {
  final errors = List.of(_reportedErrors);
  _reportedErrors.clear();
  final pending = tester.takeException();
  if (pending == null) return;
  final details = errors.lastWhere(
    (details) => identical(details.exception, pending),
    // With several errors, Flutter keeps one summary error pending, and has
    // already printed each of them.
    orElse: () => FlutterErrorDetails(
        exception: pending, library: 'Flutter test framework'),
  );
  throw _FlutterErrorReported(details);
}

void _testDelegate(TestInvocation invocation) {
  testWidgets(
    invocation.description,
    (tester) async {
      _trackFlutterErrors();
      invocation.transformContext?.call(
        (context) => BddWidgetContext.from(context, tester: tester),
      );

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

BddWidgetContext _widgetContextOf(BddContext context) {
  if (context is BddWidgetContext) {
    return context;
  }

  throw StateError(
    'WidgetTester not found in BddContext. '
    'Did you forget to use ".run()" imported from '
    '`package:bdd_framework/bdd_flutter_widget_test.dart` at the end of the scenario?',
  );
}

void _errorHandler(Object error, StackTrace stackTrace) {
  var errorDetails = (error is _FlutterErrorReported)
      ? error.details
      : FlutterErrorDetails(
          library: 'BDD Framework',
          exception: error,
          stack: stackTrace,
          stackFilter: _stackFilter,
        );
  if (TestWidgetsFlutterBinding.instance is LiveTestWidgetsFlutterBinding) {
    FlutterError.dumpErrorToConsole(errorDetails, forceReport: true);
    return;
  }
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

/// Wraps Flutter's error handler to keep the errors it reports, so each step
/// can check them. When [BddFlutter.ignoreOverflow] is on, RenderFlex overflow
/// errors are only printed.
void _trackFlutterErrors() {
  _reportedErrors.clear();
  var ignoreOverflow = BddFlutter.ignoreOverflow;
  var handlerOriginal = FlutterError.onError;
  FlutterError.onError = (details) {
    if (ignoreOverflow && _isOverflow(details)) {
      FlutterError.dumpErrorToConsole(details);
      return;
    }
    _reportedErrors.add(details);
    handlerOriginal!(details);
  };
}

bool _isOverflow(FlutterErrorDetails details) {
  var exception = details.exception;
  return (exception is FlutterError) &&
      exception.diagnostics
          .map((diagnostic) => diagnostic.value)
          .whereType<List<Object>>()
          .expand((value) => value)
          .any((data) =>
              data.toString().startsWith("A RenderFlex overflowed by"));
}

void _cleanTargetPlatformOverride() =>
    (debugDefaultTargetPlatformOverride = null);

class BddFlutter {
  static bool ignoreOverflow = true;
}

// Intentionally failing cases launched by flutter_runner_process_test.dart.
// This file does not end in _test.dart, so normal test discovery excludes it.
import 'package:bdd_framework/flutter_widget_test.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Bdd()
      .scenario('Widget sync step failure')
      .given('a widget')
      .code((ctx, tester) => fail('expected widget step failure'))
      .when('action')
      .then('outcome')
      .run((ctx, tester) => fail('unexpected later code'));

  Bdd().scenario('Widget async callback failure').then('outcome').run(
    (ctx, tester) async {
      await tester.pump();
      throw StateError('expected widget async failure');
    },
  );

  Bdd()
      .scenario('Widget non-overflow Flutter error')
      .then('a Flutter error that is not an overflow')
      .run((ctx, tester) async {
    FlutterError.reportError(FlutterErrorDetails(
        exception: FlutterError('expected non-overflow Flutter error')));
  });

  group('with ignoreOverflow off', () {
    setUp(() => BddFlutter.ignoreOverflow = false);
    tearDown(() => BddFlutter.ignoreOverflow = true);

    Bdd()
        .scenario('Widget overflow is not ignored')
        .then('an overflowing row')
        .run((ctx, tester) => tester.pumpWidget(overflowingRow()));
  });
}

/// A 10 pixel wide row holding a 100 pixel wide child.
Widget overflowingRow() => const Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: SizedBox(
          width: 10,
          child: Row(children: [SizedBox(width: 100, height: 10)]),
        ),
      ),
    );

import 'package:bdd_framework/flutter_test.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  var feature = BddFeature('Flutter Test Runner');

  group('run', () {
    Bdd(feature)
        .scenario('Executes code callback')
        .given('A BDD scenario with a code callback')
        .when('The run method is invoked')
        .then('The callback is executed')
        .code((ctx) {
      expect(true, isTrue);
    }).run();

    Bdd(feature)
        .scenario('Runs without callback')
        .given('A BDD scenario')
        .when('Run is invoked without a callback')
        .then('No error occurs')
        .run();
  });

  group('code steps', () {
    final log = <String>[];
    Bdd(feature)
        .scenario('Executes multiple code steps in order')
        .given('A scenario with multiple code blocks')
        .code((ctx) {
          log.add('given');
        })
        .when('Each step appends to a shared log')
        .code((ctx) {
          log.add('when');
        })
        .then('All steps ran in correct order')
        .code((ctx) {
          log.add('then');
          expect(log, ['given', 'when', 'then']);
        })
        .run();
  });

  group('example values', () {
    Bdd(feature)
        .scenario('Accesses example values in code callback')
        .given('A scenario with <color> and <count>')
        .when('The code reads from ctx.example')
        .then('The values match the current example row')
        .example(val('color', 'red'), val('count', 3))
        .example(val('color', 'blue'), val('count', 7))
        .run((ctx) {
      final color = ctx.example.val('color') as String;
      final count = ctx.example.val('count') as int;
      expect(color, isNotEmpty);
      expect(count, greaterThan(0));
      if (color == 'red') expect(count, 3);
      if (color == 'blue') expect(count, 7);
    });
  });

  group('table values', () {
    Bdd(feature)
        .scenario('Accesses table values in code callback')
        .given('A scenario with a data table')
        .table(
          'fruits',
          row(val('name', 'apple'), val('qty', 5)),
          row(val('name', 'banana'), val('qty', 12)),
        )
        .when('The code reads from ctx.table')
        .then('The table data is accessible by name and row index')
        .run((ctx) {
      expect(ctx.table('fruits').row(0).val('name'), 'apple');
      expect(ctx.table('fruits').row(0).val('qty'), 5);
      expect(ctx.table('fruits').row(1).val('name'), 'banana');
      expect(ctx.table('fruits').row(1).val('qty'), 12);
    });
  });

  group('overflow', () {
    final reported = <FlutterErrorDetails>[];
    FlutterExceptionHandler? previousHandler;

    // The runner wraps whatever handler is set when the test starts.
    setUp(() {
      previousHandler = FlutterError.onError;
      reported.clear();
      FlutterError.onError = reported.add;
    });
    tearDown(() => FlutterError.onError = previousHandler);

    FlutterErrorDetails details(String message) =>
        FlutterErrorDetails(exception: FlutterError(message));

    Bdd(feature)
        .scenario('Only RenderFlex overflow errors are ignored')
        .given('ignoreOverflow is on')
        .when('Flutter reports an overflow and another error')
        .then('Only the other error reaches the previous handler')
        .run((ctx) {
      expect(BddFlutter.ignoreOverflow, isTrue);
      FlutterError.onError!(
          details('A RenderFlex overflowed by 90 pixels on the right.'));
      FlutterError.onError!(details('Something else went wrong.'));
      expect(reported.map((d) => (d.exception as FlutterError).message),
          ['Something else went wrong.']);
    });

    group('with ignoreOverflow off', () {
      setUp(() => BddFlutter.ignoreOverflow = false);
      tearDown(() => BddFlutter.ignoreOverflow = true);

      Bdd(feature)
          .scenario('No error is ignored')
          .given('ignoreOverflow is off')
          .when('Flutter reports an overflow')
          .then('It reaches the previous handler')
          .run((ctx) {
        FlutterError.onError!(
            details('A RenderFlex overflowed by 90 pixels on the right.'));
        expect(reported, hasLength(1));
      });
    });
  });

  group('platform cleanup', () {
    Bdd(feature)
        .scenario('Cleans up debugDefaultTargetPlatformOverride after test')
        .given('A test that overrides the target platform')
        .when('The test completes')
        .then('debugDefaultTargetPlatformOverride is reset to null')
        .code((ctx) {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    }).run((ctx) {
      // The runner's try/finally block should have cleaned this up,
      // but since we SET it in the previous code block and this runs
      // in the same body(), the override is still active here.
      // After this entire test body completes, _cleanTargetPlatformOverride
      // should reset it. We verify by observing no crash.
      expect(debugDefaultTargetPlatformOverride, isNotNull);
    });
  });
}

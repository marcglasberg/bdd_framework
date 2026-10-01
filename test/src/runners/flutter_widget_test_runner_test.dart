import 'dart:async';

import 'package:bdd_framework/flutter_widget_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  var feature = BddFeature('Flutter Widget Test Runner');

  group('run', () {
    Bdd(feature)
        .scenario('Provides WidgetTester to run callback')
        .given('A BDD scenario with a widget test callback')
        .when('The run method is invoked')
        .then('The WidgetTester is available and functional')
        .run((ctx, tester) async {
      expect(ctx, isA<BddWidgetContext>());
      expect((ctx as BddWidgetContext).tester, same(tester));
      await tester.pumpWidget(const Directionality(
        textDirection: TextDirection.ltr,
        child: Text('Hello BDD'),
      ));
      expect(find.text('Hello BDD'), findsOneWidget);
    });

    Bdd(feature)
        .scenario('Runs without callback')
        .given('A BDD scenario')
        .when('Run is invoked without a callback')
        .then('No error occurs')
        .run();
  });

  group('scenario entry points', () {
    Bdd(feature)
        .scenario('Widget When entry')
        .when('pump widget')
        .code((ctx, tester) async {
          await tester.pumpWidget(const Directionality(
            textDirection: TextDirection.ltr,
            child: Text('When entry'),
          ));
        })
        .then('widget is visible')
        .code((ctx, tester) {
          expect(find.text('When entry'), findsOneWidget);
          expect((ctx as BddWidgetContext).tester, same(tester));
        })
        .run();

    Bdd(feature)
        .scenario('Widget Then entry')
        .then('pump and find widget')
        .code((ctx, tester) async {
      await tester.pumpWidget(const Directionality(
        textDirection: TextDirection.ltr,
        child: Text('Then entry'),
      ));
      expect(find.text('Then entry'), findsOneWidget);
      expect((ctx as BddWidgetContext).tester, same(tester));
    }).run();
  });

  group('code steps', () {
    Bdd(feature)
        .scenario('Provides WidgetTester in code step')
        .given('A scenario with a widget code block')
        .code((ctx, tester) async {
          await tester.pumpWidget(const Directionality(
            textDirection: TextDirection.ltr,
            child: Text('Code Step'),
          ));
          expect(find.text('Code Step'), findsOneWidget);
        })
        .when('The code step executes')
        .then('The tester is available')
        .run();

    var step1Ran = false;
    var step2Ran = false;
    Bdd(feature)
        .scenario('Multiple code steps all receive tester')
        .given('A scenario with multiple widget code blocks')
        .code((ctx, tester) async {
          step1Ran = true;
          await tester.pumpWidget(const Directionality(
            textDirection: TextDirection.ltr,
            child: Text('Step 1'),
          ));
          expect(find.text('Step 1'), findsOneWidget);
        })
        .when('Each step uses the tester')
        .code((ctx, tester) async {
          step2Ran = true;
          await tester.pumpWidget(const Directionality(
            textDirection: TextDirection.ltr,
            child: Text('Step 2'),
          ));
          expect(find.text('Step 2'), findsOneWidget);
        })
        .then('All steps executed with a valid tester')
        .run((ctx, tester) async {
          expect(step1Ran, isTrue);
          expect(step2Ran, isTrue);
        });

    test('throws a helpful error when widget code runs without widget runner',
        () async {
      final reporter = _NoOpBddReporter();

      final error = await _captureAsyncError(() {
        Bdd(feature)
            .scenario('Widget code without widget runner')
            .given('A widget-specific code step')
            .code((ctx, tester) {})
            .when('The scenario runs through testRun')
            .then('A helpful error is thrown')
            .testRun((ctx) {}, reporter);
      });

      expect(
        error,
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('WidgetTester not found in BddContext'),
        ),
      );
    });
  });

  group('example values', () {
    Bdd(feature)
        .scenario('Accesses example values in widget test')
        .given('A scenario with <label>')
        .when('The widget displays the example value')
        .then('The example value drives the widget content')
        .example(val('label', 'Alpha'))
        .example(val('label', 'Beta'))
        .run((ctx, tester) async {
      final label = ctx.example.val('label') as String;
      await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: Text(label),
      ));
      expect(find.text(label), findsOneWidget);
    });
  });

  group('table values', () {
    Bdd(feature)
        .scenario('Accesses table values in widget test')
        .given('A scenario with a data table')
        .table(
          'items',
          row(val('name', 'widget_a'), val('visible', true)),
          row(val('name', 'widget_b'), val('visible', false)),
        )
        .when('The code reads from ctx.table')
        .then('The table data is accessible')
        .run((ctx, tester) async {
      expect(ctx.table('items').row(0).val('name'), 'widget_a');
      expect(ctx.table('items').row(0).val('visible'), true);
      expect(ctx.table('items').row(1).val('name'), 'widget_b');
      expect(ctx.table('items').row(1).val('visible'), false);
    });
  });
}

class _NoOpBddReporter extends BddReporter {
  @override
  Future<void> report() async {}
}

Future<Object> _captureAsyncError(void Function() action) async {
  final completer = Completer<Object>();

  await runZonedGuarded(() async {
    action();
    await Future<void>.delayed(Duration.zero);
  }, (error, stackTrace) {
    if (!completer.isCompleted) {
      completer.complete(error);
    }
  });

  return completer.future;
}

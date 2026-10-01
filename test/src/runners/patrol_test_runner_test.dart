import 'dart:async';

import 'package:bdd_framework/patrol_test.dart';
import 'package:patrol/patrol.dart';
import 'package:test/test.dart';

void main() {
  var feature = BddFeature('Patrol Test Runner');

  group('context transformation', () {
    test('creates a patrol context from an existing bdd context', () {
      final baseContext = BddContext(
        BddTableValues({'name': 'demo'}),
        BddMultipleTableValues({}),
      );
      final patrolTester = _FakePatrolIntegrationTester();

      final patrolContext = BddPatrolContext.from(
        baseContext,
        patrolTester: patrolTester,
      );

      expect(patrolContext.example.val('name'), 'demo');
      expect(patrolContext.patrolTester, same(patrolTester));
    });

    test('patrol code receives transformed patrol context', () async {
      final bdd = Bdd(feature)
          .scenario('Patrol context transformation')
          .given('A patrol code block')
          .code((ctx, patrolTester) {
            expect(ctx, isA<BddPatrolContext>());
            expect((ctx as BddPatrolContext).patrolTester, same(patrolTester));
          })
          .when('The runner transforms the context')
          .then('The patrol tester is available in the code block')
          .bdd;

      final patrolTester = _FakePatrolIntegrationTester();

      BddRunner().run(
        bdd,
        (ctx) {
          expect(ctx, isA<BddPatrolContext>());
          expect((ctx as BddPatrolContext).patrolTester, same(patrolTester));
        },
        (invocation) async {
          invocation.transformContext?.call(
            (context) => BddPatrolContext.from(
              context,
              patrolTester: patrolTester,
            ),
          );
          await invocation.body();
        },
        null,
      );
    });
  });

  group('scenario entry points', () {
    for (final keyword in ['When', 'Then']) {
      test('transforms Patrol context for a $keyword start', () async {
        final bdd = Bdd(feature);
        final scenario = bdd.scenario('Patrol $keyword entry');
        final tester = _FakePatrolIntegrationTester();
        PatrolIntegrationTester? received;
        final PatrolTestCallback callback = (ctx, patrolTester) {
          received = patrolTester;
          expect((ctx as BddPatrolContext).patrolTester, same(tester));
        };
        if (keyword == 'When') {
          scenario.when('action').code(callback);
        } else {
          scenario.then('outcome').code(callback);
        }
        final invocations = <TestInvocation>[];
        BddRunner().run(bdd, (_) {}, invocations.add, null, () => true);
        final invocation = invocations.single;
        invocation.transformContext!(
            (context) => BddPatrolContext.from(context, patrolTester: tester));
        await invocation.body();
        expect(received, same(tester));
        expect(bdd.passed, [true]);
      });
    }
  });

  group('misuse feedback', () {
    test('throws a helpful error when patrol code runs without patrol runner',
        () async {
      final reporter = _NoOpBddReporter();

      final error = await _captureAsyncError(() {
        Bdd(feature)
            .scenario('Patrol code without patrol runner')
            .given('A patrol-specific code step')
            .code((ctx, patrolTester) {})
            .when('The scenario runs through testRun')
            .then('A helpful error is thrown')
            .testRun((ctx) {}, reporter);
      });

      expect(
        error,
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('PatrolIntegrationTester not found in BddContext'),
        ),
      );
    });
  });
}

class _NoOpBddReporter extends BddReporter {
  @override
  Future<void> report() async {}
}

class _FakePatrolIntegrationTester implements PatrolIntegrationTester {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
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

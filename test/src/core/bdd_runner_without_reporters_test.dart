import 'dart:async';
import 'dart:io';

import 'package:bdd_framework/dart_test.dart';
import 'package:test/test.dart';

void main() {
  setUp(() => BddReporter.set());
  tearDown(() => BddReporter.set());

  test(
    'without reporters, steps keep their order and do not open files',
    () async {
      final events = <String>[];
      final feature = BddFeature('No reporter');
      feature.background.given('background').code((_) {
        events.add('background');
      });
      final bdd = Bdd(feature)
          .scenario('ordered code')
          .given('async step')
          .code((_) async {
            events.add('async start');
            await Future<void>.value();
            events.add('async end');
          })
          .then('sync step')
          .code((_) => events.add('sync'))
          .bdd;
      late TestInvocation invocation;
      BddRunner().run(
        bdd,
        (_) => events.add('callback'),
        (value) => invocation = value,
        null,
        () => true,
      );

      await _withoutFilesystem(invocation.body);

      expect(events, [
        'background',
        'async start',
        'async end',
        'sync',
        'callback',
      ]);
      expect(bdd.passed, [true]);
      final execution = bdd.executions.single;
      expect(execution.passed, isTrue);
      expect(execution.codeExecutions, hasLength(4));
      expect(execution.codeExecutions.every((code) => code.passed), isTrue);
      expect(execution.duration, isNotNull);
      expect(execution.callbackResults, hasLength(1));
      expect(() => bdd.executions.clear(), throwsUnsupportedError);
      expect(() => execution.codeExecutions.clear(), throwsUnsupportedError);
    },
  );

  for (final asynchronous in [false, true]) {
    for (final location in ['background', 'step', 'callback']) {
      test(
        'without reporters, $location failure propagates (async=$asynchronous)',
        () async {
          final events = <String>[];
          final failure = StateError('synthetic $location failure');
          final feature = BddFeature('No reporter failure');
          FutureOr<void> action(String name) {
            events.add(name);
            if (name == location) {
              if (asynchronous) {
                return Future<void>.value().then((_) => throw failure);
              }
              throw failure;
            }
          }

          feature.background
              .given('background')
              .code((_) => action('background'));
          final bdd = Bdd(feature)
              .scenario('failure')
              .given('first step')
              .code((_) => action('step'))
              .then('later step')
              .code((_) => action('later'))
              .bdd;
          late TestInvocation invocation;
          Object? handled;
          StackTrace? handledStack;
          BddRunner().run(
            bdd,
            (_) => action('callback'),
            (value) => invocation = value,
            (error, stack) {
              handled = error;
              handledStack = stack;
            },
            () => true,
          );

          await expectLater(
            _withoutFilesystem(invocation.body),
            throwsA(isA<TestFailure>()),
          );

          expect(handled, same(failure));
          expect(handledStack, isNotNull);
          expect(events, switch (location) {
            'background' => ['background'],
            'step' => ['background', 'step'],
            _ => ['background', 'step', 'later', 'callback'],
          });
          expect(bdd.passed, [false]);
          final execution = bdd.executions.single;
          expect(execution.passed, isFalse);
          expect(execution.error, same(failure));
          expect(execution.codeExecutions.last.error, same(failure));
          expect(execution.codeExecutions.last.isFinished, isTrue);
        },
      );
    }
  }

  test(
    'without reporters, a synchronous first failure is recorded immediately',
    () async {
      final failure = StateError('synthetic synchronous failure');
      final bdd = Bdd(BddFeature('Immediate failure'))
          .scenario('first step throws')
          .given('failing step')
          .code((_) => throw failure)
          .then('unreached step')
          .bdd;
      late TestInvocation invocation;
      BddRunner().run(
        bdd,
        (_) {},
        (value) => invocation = value,
        (_, __) {},
        () => true,
      );

      final completion = _withoutFilesystem(invocation.body);
      expect(bdd.passed, [false]);
      expect(bdd.executions.single.error, same(failure));
      await expectLater(completion, throwsA(isA<TestFailure>()));
    },
  );

  test(
    'without reporters, examples and retries keep separate executions',
    () async {
      final calls = <int>[];
      final bdd = Bdd(BddFeature('No reporter retries'))
          .scenario('rows')
          .then('row runs')
          .example(val('n', 1))
          .example(val('n', 2))
          .bdd;
      final invocations = <TestInvocation>[];
      BddRunner().run(
        bdd,
        (ctx) {
          calls.add(ctx.example.val('n') as int);
          if (calls.length == 1)
            throw StateError('synthetic first attempt failure');
        },
        invocations.add,
        (_, __) {},
        () => true,
      );

      await expectLater(
        _withoutFilesystem(invocations[0].body),
        throwsA(isA<TestFailure>()),
      );
      await _withoutFilesystem(invocations[0].body);
      await _withoutFilesystem(invocations[1].body);

      expect(calls, [1, 1, 2]);
      expect(bdd.passed, [false, true, true]);
      expect(
        bdd.executions.map(
          (run) => (run.exampleIndex, run.attempt, run.passed),
        ),
        [(0, 1, false), (0, 2, true), (1, 1, true)],
      );
    },
  );
}

Future<void> _withoutFilesystem(Future<void> Function() body) =>
    IOOverrides.runZoned(
      body,
      createFile: (_) => throw StateError('Unexpected file access'),
      createDirectory: (_) => throw StateError('Unexpected directory access'),
    );

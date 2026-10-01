import 'dart:async';
import 'package:bdd_framework/bdd_framework.dart';
import 'package:test/test.dart';

void main() {
  group('BddRunner', () {
    late BddRunner runner;
    late BddFeature feature;

    setUp(() {
      runner = BddRunner();
      feature = BddFeature('Test Feature');
      // Reset reporters and runInfo for clean tests.
      BddReporter.set();
      BddReporter.runInfo.testCount = 0;
      BddReporter.runInfo.totalTestCount = 0;
      BddReporter.runInfo.passedCount = 0;
      BddReporter.runInfo.failedCount = 0;
      BddReporter.runInfo.skipCount = 0;
    });

    // ── Utility methods ─────────────────────────────────────────────────

    group('subscript', () {
      test('converts single digit to subscript character', () {
        expect(runner.subscript(0), '₀');
        expect(runner.subscript(9), '₉');
      });

      test('converts multi-digit number to subscript string', () {
        expect(runner.subscript(10), '₁₀');
        expect(runner.subscript(123), '₁₂₃');
      });
    });

    group('testCountStr', () {
      test('returns only count when exampleNumber is null', () {
        expect(runner.testCountStr(5, null), '5');
      });

      test('appends incremented subscript when exampleNumber is provided', () {
        // exampleNumber is 0-based; displayed as 1-based subscript.
        expect(runner.testCountStr(5, 0), '5₁');
        expect(runner.testCountStr(5, 9), '5₁₀');
      });
    });

    // ── Run loop orchestration ──────────────────────────────────────────

    group('run loop', () {
      test('invokes testDelegate exactly once when no examples exist', () {
        int delegateCalls = 0;
        final bdd = Bdd(feature)
            .scenario('No examples')
            .given('a precondition')
            .when('an action')
            .then('an outcome')
            .bdd;

        runner.run(
          bdd,
          (ctx) {},
          (invocation) {
            delegateCalls++;
          },
          null,
        );

        expect(delegateCalls, 1);
        expect(BddReporter.runInfo.testCount, 1);
        expect(BddReporter.runInfo.totalTestCount, 1);
      });

      test('invokes testDelegate once per example row', () {
        int delegateCalls = 0;
        // .example() is available on BddThen, so chain through then().
        final bdd = Bdd(feature)
            .scenario('With examples')
            .given('a precondition')
            .when('an action')
            .then('an outcome')
            .example(val('a', 1))
            .example(val('a', 2))
            .example(val('a', 3))
            .bdd;

        runner.run(
          bdd,
          (ctx) {},
          (invocation) {
            delegateCalls++;
          },
          null,
        );

        expect(delegateCalls, 3);
        expect(BddReporter.runInfo.testCount, 1);
        expect(BddReporter.runInfo.totalTestCount, 3);
      });

      test('registers bdd with all active reporters', () {
        // _addBdd is library-private, verify indirectly via reporter.features.
        final reporter = _IndirectReporter();
        BddReporter.set(reporter);
        final bdd = Bdd(feature)
            .scenario('Reporter test')
            .given('G')
            .when('W')
            .then('T')
            .bdd;

        runner.run(
          bdd,
          (ctx) {},
          (invocation) {},
          null,
        );

        // After run, the bdd should have been registered.
        final registeredBdds = reporter.features.expand((f) => f.bdds).toList();
        expect(registeredBdds, contains(bdd));
      });

      test('adds provided code to bdd.codeRuns', () {
        final bdd = Bdd(feature)
            .scenario('Code run test')
            .given('G')
            .when('W')
            .then('T')
            .bdd;

        CodeRun myCode = (ctx) {};
        runner.run(
          bdd,
          myCode,
          (invocation) {},
          null,
        );

        expect(bdd.codeRuns, contains(myCode));
      });
    });

    // ── Context initialization ──────────────────────────────────────────

    group('context initialization', () {
      test('provides correct example values for each iteration', () {
        final bdd = Bdd(feature)
            .scenario('Example context')
            .given('G')
            .when('W')
            .then('T')
            .example(val('color', 'red'))
            .example(val('color', 'blue'))
            .bdd;

        final capturedValues = <String?>[];

        runner.run(
          bdd,
          (ctx) {
            capturedValues.add(ctx.example.val('color') as String?);
          },
          (invocation) async {
            await invocation.body();
          },
          null,
        );

        expect(capturedValues, ['red', 'blue']);
      });

      test('passes table data to BddContext', () {
        // .table() is available on BddGiven.
        final bdd = Bdd(feature)
            .scenario('Table context')
            .given('G')
            .table('Items', row(val('name', 'apple'), val('qty', 3)))
            .when('W')
            .then('T')
            .bdd;

        BddContext? capturedCtx;
        runner.run(
          bdd,
          (ctx) {
            capturedCtx = ctx;
          },
          (invocation) async {
            await invocation.body();
          },
          null,
        );

        expect(capturedCtx, isNotNull);
        expect(capturedCtx!.table('Items').row(0).val('name'), 'apple');
        expect(capturedCtx!.table('Items').row(0).val('qty'), 3);
      });

      test('uses the context configured by testDelegate during execution', () async {
        final bdd = Bdd(feature)
            .scenario('Configured context')
            .given('G')
            .when('W')
            .then('T')
            .bdd;

        BddContext? capturedCtx;
        final configuredCtx = _ConfiguredBddContext(
          BddTableValues.from(null),
          BddMultipleTableValues({}),
          marker: 'configured',
        );

        runner.run(
          bdd,
          (ctx) {
            capturedCtx = ctx;
          },
          (invocation) async {
            invocation.transformContext?.call((_) => configuredCtx);
            await invocation.body();
          },
          null,
        );

        expect(capturedCtx, same(configuredCtx));
      });
    });

    // ── Execution order and async handling ───────────────────────────────

    group('execution order', () {
      test('executes codeTerms before codeRuns', () {
        final log = <String>[];
        final bdd = Bdd(feature)
            .scenario('Order test')
            .given('G')
            .code((ctx) => log.add('codeTerm'))
            .when('W')
            .then('T')
            .bdd;

        runner.run(
          bdd,
          (ctx) => log.add('codeRun'),
          (invocation) async {
            await invocation.body();
            // Verify inside the delegate after body() completes.
            expect(log, ['codeTerm', 'codeRun']);
          },
          null,
        );
      });

      test('awaits asynchronous code runs', () {
        bool finished = false;
        final bdd = Bdd(feature)
            .scenario('Async test')
            .given('G')
            .when('W')
            .then('T')
            .bdd;

        runner.run(
          bdd,
          (ctx) async {
            await Future.delayed(const Duration(milliseconds: 10));
            finished = true;
          },
          (invocation) async {
            await invocation.body();
            // Verify inside the delegate after body() completes.
            expect(finished, isTrue);
          },
          null,
        );
      });
    });

    // ── Error handling ──────────────────────────────────────────────────

    group('error handling', () {
      test('marks bdd as failed when exception occurs', () {
        final bdd = Bdd(feature)
            .scenario('Fail test')
            .given('G')
            .when('W')
            .then('T')
            .bdd;

        runner.run(
          bdd,
          (ctx) => throw Exception('boom'),
          (invocation) async {
            await invocation.body();
          },
          (e, s) {},
        );

        expect(bdd.passed, [false]);
        expect(BddReporter.runInfo.failedCount, 1);
      });

      test('invokes custom errorHandler with error and stackTrace', () {
        Object? capturedError;
        StackTrace? capturedStack;
        final bdd = Bdd(feature)
            .scenario('Handler test')
            .given('G')
            .when('W')
            .then('T')
            .bdd;

        runner.run(
          bdd,
          (ctx) => throw Exception('Target Error'),
          (invocation) async {
            await invocation.body();
          },
          (error, stack) {
            capturedError = error;
            capturedStack = stack;
          },
        );

        expect(capturedError.toString(), contains('Target Error'));
        expect(capturedStack, isNotNull);
      });

      test('prints error when no errorHandler is provided', () {
        final output = <String>[];
        runZoned(
          () {
            final bdd = Bdd(feature)
                .scenario('No handler test')
                .given('G')
                .when('W')
                .then('T')
                .bdd;

            runner.run(
              bdd,
              (ctx) => throw Exception('PrintedError'),
              (invocation) async {
                await invocation.body();
              },
              null,
            );
          },
          zoneSpecification: ZoneSpecification(
            print: (self, parent, zone, s) => output.add(s),
          ),
        );

        expect(output.any((s) => s.contains('PrintedError')), isTrue);
      });
    });

    // ── Error propagation policy ─────────────────────────────────────────

    group('error propagation policy', () {
      for (final policy in <bool?>[null, false, true]) {
        test('records and handles failure with rethrow policy $policy', () async {
          final bdd = Bdd(feature).scenario('policy').then('failure').bdd;
          final original = StateError('original failure');
          final stack = StackTrace.fromString('original failure stack');
          final invocations = <TestInvocation>[];
          Object? handled;
          StackTrace? handledStack;
          runner.run(bdd, (_) => Error.throwWithStackTrace(original, stack),
              invocations.add, (error, trace) {
            handled = error;
            handledStack = trace;
          }, policy == null ? null : () => policy);
          if (policy == true) {
            Object? propagated;
            StackTrace? propagatedStack;
            try {
              await invocations.single.body();
            } catch (error, trace) {
              propagated = error;
              propagatedStack = trace;
            }
            expect(propagated, isA<TestFailure>());
            expect(propagatedStack.toString(), contains('original failure stack'));
          } else {
            await invocations.single.body();
          }
          expect(handled, same(original));
          expect(handledStack.toString(), contains('original failure stack'));
          expect(bdd.passed, [false]);
          expect(BddReporter.runInfo.failedCount, 1);
          expect(BddReporter.runInfo.passedCount, 0);
        });
      }

      test('evaluates rethrow policy after the handler', () async {
        final bdd = Bdd(feature).scenario('policy order').then('failure').bdd;
        final invocations = <TestInvocation>[];
        var handled = false;
        runner.run(bdd, (_) => throw StateError('failure'), invocations.add,
            (error, stack) => handled = true, () => handled);
        await expectLater(invocations.single.body(), throwsA(isA<TestFailure>()));
        expect(handled, isTrue);
        expect(bdd.passed, [false]);
      });

      test('propagates exceptions thrown by an error handler', () async {
        final bdd = Bdd(feature).scenario('handler failure').then('failure').bdd;
        final invocations = <TestInvocation>[];
        final handlerFailure = StateError('handler failure');
        runner.run(bdd, (_) => throw StateError('step failure'), invocations.add,
            (error, stack) => throw handlerFailure);
        await expectLater(invocations.single.body(), throwsA(same(handlerFailure)));
        expect(bdd.passed, [false]);
      });
    });

    // ── Retry and config ────────────────────────────────────────────────

    group('retry and timeout config', () {
      test('passes timeout from bdd config to testDelegate', () {
        final bdd = Bdd(feature)
            .scenario('Timeout test')
            .given('G')
            .when('W')
            .then('T')
            .bdd;
        bdd.timeout(const Duration(seconds: 42));

        Timeout? receivedTimeout;
        runner.run(
          bdd,
          (ctx) {},
          (invocation) {
            receivedTimeout = invocation.timeout;
          },
          null,
        );

        expect(receivedTimeout?.duration, const Duration(seconds: 42));
      });
    });

    // ── Skip ────────────────────────────────────────────────────────────

    group('skip behavior', () {
      test('increments skipCount and passes skip flag to delegate', () {
        final bdd = Bdd(feature)
            .scenario('Skipped test')
            .given('G')
            .when('W')
            .then('T')
            .bdd;
        bdd.skip;

        bool? receivedSkip;
        runner.run(
          bdd,
          (ctx) {},
          (invocation) {
            receivedSkip = invocation.skip;
          },
          null,
        );

        expect(receivedSkip, isTrue);
        expect(BddReporter.runInfo.skipCount, 1);
      });
    });

    // ── RunInfo counters ────────────────────────────────────────────────

    group('runInfo counters', () {
      test('accumulates correctly across multiple scenarios', () {
        final bdd1 =
            Bdd(feature).scenario('Passed').given('G').when('W').then('T').bdd;
        final bdd2 =
            Bdd(feature).scenario('Failed').given('G').when('W').then('T').bdd;
        final bdd3 =
            Bdd(feature).scenario('Skipped').given('G').when('W').then('T').bdd;
        bdd3.skip;

        // Run passing test — verify passedCount inside delegate after body.
        runner.run(
          bdd1,
          (ctx) {},
          (invocation) async {
            await invocation.body();
            expect(BddReporter.runInfo.passedCount, 1);
          },
          null,
        );
        // Run failing test — verify failedCount inside delegate after body.
        runner.run(
          bdd2,
          (ctx) => throw Exception('Err'),
          (invocation) async {
            await invocation.body();
            expect(BddReporter.runInfo.failedCount, 1);
          },
          (e, s) {},
        );
        // Run skipped test — body is not called by the test framework.
        runner.run(
          bdd3,
          (ctx) {},
          (invocation) {},
          null,
        );

        // These counters are set synchronously in run().
        expect(BddReporter.runInfo.testCount, 3);
        expect(BddReporter.runInfo.skipCount, 1);
        expect(BddReporter.runInfo.totalTestCount, 3);
      });
    });

    // ── Console output ──────────────────────────────────────────────────

    group('console output', () {
      test('header and footer include test number and ANSI colors', () {
        final output = <String>[];
        runZoned(
          () {
            final bdd = Bdd(feature)
                .scenario('Output test')
                .given('G')
                .when('W')
                .then('T')
                .bdd;

            runner.run(
              bdd,
              (ctx) {},
              (invocation) async {
                await invocation.body();
                // Verify inside delegate after body prints footer.
                final joined = output.join('\n');
                expect(joined, contains('TEST 1'));
                expect(joined, contains('PASSED'));
                // Verify ANSI blue color code is present.
                expect(joined, contains('\x1B[38;5;45m'));
              },
              null,
            );
          },
          zoneSpecification: ZoneSpecification(
            print: (self, parent, zone, s) => output.add(s),
          ),
        );
      });

      test('header shows SKIPPED label for skipped tests', () {
        final output = <String>[];
        runZoned(
          () {
            final bdd = Bdd(feature)
                .scenario('Skip output test')
                .given('G')
                .when('W')
                .then('T')
                .bdd;
            bdd.skip;

            runner.run(
              bdd,
              (ctx) {},
              (invocation) async {
                await invocation.body();
              },
              null,
            );
          },
          zoneSpecification: ZoneSpecification(
            print: (self, parent, zone, s) => output.add(s),
          ),
        );

        // The header is printed synchronously at the start of body(), so
        // even though skip means the real test framework won't call body(),
        // here our mock delegate DOES call body() to test output.
        final joined = output.join('\n');
        expect(joined, contains('SKIPPED'));
      });

      test('fail output includes FAILED label', () {
        final output = <String>[];
        runZoned(
          () {
            final bdd = Bdd(feature)
                .scenario('Fail output test')
                .given('G')
                .when('W')
                .then('T')
                .bdd;

            runner.run(
              bdd,
              (ctx) => throw Exception('TestFailure'),
              (invocation) async {
                await invocation.body();
                // Verify inside delegate after body prints fail output.
                final joined = output.join('\n');
                expect(joined, contains('FAILED'));
              },
              (e, s) {},
            );
          },
          zoneSpecification: ZoneSpecification(
            print: (self, parent, zone, s) => output.add(s),
          ),
        );
      });
    });
  });
}

/// A reporter used to indirectly verify that [BddRunner.run] calls _addBdd.
/// Since _addBdd is library-private we cannot override it, but we can inspect
/// the public [features] set that _addBdd populates.
class _IndirectReporter extends BddReporter {
  @override
  Future<void> report() async {}
}

class _ConfiguredBddContext extends BddContext {
  _ConfiguredBddContext(
    BddTableValues example,
    BddMultipleTableValues tables, {
    required this.marker,
  }) : super(example, tables);

  final String marker;
}

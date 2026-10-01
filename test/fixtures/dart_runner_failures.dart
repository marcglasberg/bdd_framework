// Intentionally failing cases launched by dart_test_runner_process_test.dart.
// This file does not end in _test.dart, so normal test discovery excludes it.
import 'package:bdd_framework/dart_test.dart';
import 'package:test/test.dart';

void main() {
  final scenarios = <BddFramework>[];
  BddReporter.set(_ResultReporter());
  for (final keyword in ['When', 'Then']) {
    for (final asynchronous in [false, true]) {
      final mode = asynchronous ? 'async' : 'sync';
      for (final location in ['step', 'background', 'callback']) {
        final name = '$keyword $mode $location failure';
        final feature = BddFeature(name);
        final bdd = Bdd(feature);
        scenarios.add(bdd);
        final CodeRun failure = asynchronous
            ? (_) async {
                await Future<void>.delayed(Duration.zero);
                throw StateError('expected failure: $name');
              }
            : (_) => fail('expected failure: $name');
        if (location == 'background') {
          feature.background.given('failing setup').code(failure);
        }
        final scenario = bdd.scenario(name);
        if (keyword == 'When') {
          scenario
              .when('action')
              .code(location == 'step' ? failure : (_) {})
              .then('outcome')
              .run(location == 'callback'
                  ? failure
                  : (_) {
                      fail('unexpected later code: $name');
                    });
        } else {
          scenario
              .then('outcome')
              .code(location == 'step' ? failure : (_) {})
              .run(location == 'callback'
                  ? failure
                  : (_) {
                      fail('unexpected later code: $name');
                    });
        }
      }
    }
  }
  final examples = Bdd(BddFeature('examples'));
  examples
      .scenario('example failure')
      .then('row succeeds')
      .code((ctx) {
        expect(ctx.example.val('row'), 2,
            reason: 'expected failure: example row');
      })
      .example(val('row', 1))
      .example(val('row', 2))
      .run();
  tearDown(() => print('fixture teardown completed'));
  tearDownAll(() {
    for (final bdd in scenarios) {
      expect(bdd.passed, [false], reason: bdd.description());
    }
    expect(examples.passed, [false, true]);
    expect(BddReporter.runInfo.failedCount, 13);
    expect(BddReporter.runInfo.passedCount, 1);
  });
  BddReporter.reportAll();
}

class _ResultReporter extends BddReporter {
  @override
  Future<void> report() async {
    expect(features.length, 13);
    expect(features.expand((feature) => feature.testResults).length, 13);
    print('fixture reporter completed');
  }
}

import 'package:bdd_framework/bdd_framework.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    BddReporter.set();
    BddReporter.runInfo.passedCount = 0;
    BddReporter.runInfo.failedCount = 0;
  });
  test('traditional Given/When/Then renders every term', () {
    final bdd = Bdd()
        .scenario('flow')
        .given('condition')
        .when('action')
        .then('result')
        .bdd;
    expect(
        bdd.toString(),
        '  Scenario: flow\n    Given condition\n'
        '    When action\n    Then result\n');
  });
  for (final keyword in ['When', 'Then']) {
    group('$keyword entry', () {
      BddThen start(BddFramework bdd) {
        final scenario = bdd.scenario('flow');
        return keyword == 'When'
            ? scenario.when('action').then('result')
            : scenario.then('result');
      }

      test('renders full chain without introducing Given', () {
        final bdd = Bdd();
        start(bdd).and('also').but('except').note('context');
        expect(bdd.allTerms<BddGiven>(), isEmpty);
        expect(
            bdd.toString(),
            '  Scenario: flow\n'
            '${keyword == 'When' ? '    When action\n' : ''}'
            '    Then result\n    And also\n    But except\n    # Context\n');
        final styled = bdd.toString(config: BddRunner.config);
        expect(
            styled,
            contains(
                '${BddRunner.boldItalic}Then${BddRunner.boldItalicOff} result'));
        expect(styled, isNot(contains('Given')));
      });
      test('awaits background and chained steps for every example', () async {
        final feature = BddFeature('runtime');
        final events = <String>[];
        feature.background.given('setup').code((ctx) async {
          await Future<void>.delayed(Duration.zero);
          events.add('background:${ctx.example.val('n')}');
        });
        final bdd = Bdd(feature);
        start(bdd)
            .code((ctx) async {
              await Future<void>.delayed(Duration.zero);
              events.add('step:${ctx.example.val('n')}');
            })
            .and('also')
            .code((_) => events.add('and'))
            .but('except')
            .code((_) => events.add('but'))
            .example(val('n', 1))
            .example(val('n', 2));
        await _execute(bdd, (_) => events.add('callback'));
        expect(events, [
          'background:1',
          'step:1',
          'and',
          'but',
          'callback',
          'background:2',
          'step:2',
          'and',
          'but',
          'callback'
        ]);
        expect(bdd.passed, [true, true]);
        expect(BddReporter.runInfo.passedCount, 2);
      });
      test('async step failure stops later code and records failure', () async {
        final bdd = Bdd();
        var ranLater = false;
        start(bdd)
            .code((_) async {
              await Future<void>.delayed(Duration.zero);
              throw StateError('step failure');
            })
            .and('never execute')
            .code((_) => ranLater = true);
        await expectLater(
            _execute(bdd, (_) => ranLater = true), throwsA(isA<TestFailure>()));
        expect(ranLater, isFalse);
        expect(bdd.passed, [false]);
        expect(BddReporter.runInfo.failedCount, 1);
        expect(BddReporter.runInfo.passedCount, 0);
      });
      test('failed background prevents execution of scenario code', () async {
        final feature = BddFeature('failed setup');
        feature.background
            .given('setup')
            .code((_) => throw StateError('setup'));
        final bdd = Bdd(feature);
        var ran = false;
        start(bdd).code((_) => ran = true);
        await expectLater(_execute(bdd, (_) {}), throwsA(isA<TestFailure>()));
        expect(ran, isFalse);
        expect(bdd.passed, [false]);
      });
      test('table values and reporter results are available without Given',
          () async {
        final reporter = _Reporter();
        BddReporter.set(reporter);
        final bdd = Bdd(BddFeature('tables'));
        start(bdd).table('data', row(val('v', 42))).code((ctx) {
          expect(ctx.table('data').row(0).val('v'), 42);
        });
        await _execute(bdd, (_) {});
        expect(bdd.passed, [true]);
        expect(reporter.features.single.testResults.single.passed, [true]);
      });
    });
  }
  test('When completes asynchronous action before Then executes', () async {
    final bdd = Bdd();
    final events = <String>[];
    bdd
        .scenario('async action')
        .when('action')
        .code((_) async {
          events.add('start');
          await Future<void>.delayed(Duration.zero);
          events.add('done');
        })
        .then('result')
        .code((_) => events.add('then'));
    await _execute(bdd, (_) {});
    expect(events, ['start', 'done', 'then']);
    expect(bdd.passed, [true]);
  });
  group('Flutter lifecycle', () {
    final events = <String>[];
    setUpAll(() => events.add('setupAll'));
    setUp(() => events.add('setup'));
    tearDown(() => events.add('teardown'));
    tearDownAll(() {
      expect(events, [
        'setupAll',
        'setup',
        'when',
        'teardown',
        'setup',
        'then',
        'teardown'
      ]);
    });
    Bdd().scenario('When runs').when('action').run((_) async {
      await Future<void>.delayed(Duration.zero);
      events.add('when');
    });
    Bdd().scenario('Then runs').then('outcome').run((_) => events.add('then'));
    Bdd()
        .skip
        .scenario('skip')
        .then('never execute')
        .run((_) => fail('skipped step ran'));
  });
}

Future<void> _execute(BddFramework bdd, CodeRun finalCode) async {
  final invocations = <TestInvocation>[];
  BddRunner().run(bdd, finalCode, invocations.add, null, () => true);
  for (final invocation in invocations) {
    await invocation.body();
  }
}

class _Reporter extends BddReporter {
  @override
  Future<void> report() async {}
}

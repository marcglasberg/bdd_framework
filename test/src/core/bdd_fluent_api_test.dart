// Walks every method of the fluent API (after a step, after `.code()` and
// after a table), checking what each one renders and that code blocks run in
// order with access to every table.
import 'package:bdd_framework/dart_test.dart';
import 'package:test/test.dart';

void main() {
  setUp(() {
    BddReporter.set();
    BddReporter.runInfo
      ..testCount = 0
      ..totalTestCount = 0
      ..passedCount = 0
      ..failedCount = 0
      ..skipCount = 0;
  });

  test('a scenario can start with a note', () {
    final bdd = Bdd()
        .scenario('s')
        .note('about this scenario')
        .when('action')
        .then('result')
        .bdd;

    expect(
      bdd.toString(),
      '  Scenario: s\n'
      '    # About this scenario\n'
      '    When action\n'
      '    Then result\n',
    );
  });

  test('every method after a code block', () {
    final log = <String>[];
    final reporter = _NoOpReporter();

    final bdd = Bdd()
        .scenario('after code')
        .given('g')
        .code((_) => log.add('given'))
        .table('given table', row(val('a', 1)))
        .and('g and')
        .code((_) => log.add('given and'))
        .but('g but')
        .code((_) => log.add('given but'))
        .note('g note')
        .when('w')
        .code((_) => log.add('when'))
        .table('when table', row(val('b', 2)))
        .and('w and')
        .code((_) => log.add('when and'))
        .and('w and 2')
        .code((_) => log.add('when and 2'))
        .but('w but')
        .code((_) => log.add('when but'))
        .note('w note')
        .then('t')
        .code((_) => log.add('then'))
        .table('then table', row(val('c', 3)))
        .and('t and')
        .code((_) => log.add('then and'))
        .note('t note')
        .testRun((ctx) {
      log.add('run');
      expect(ctx.table('given table').row(0).val('a'), 1);
      expect(ctx.table('when table').row(0).val('b'), 2);
      expect(ctx.table('then table').row(0).val('c'), 3);
    }, reporter);

    expect(log, [
      'given',
      'given and',
      'given but',
      'when',
      'when and',
      'when and 2',
      'when but',
      'then',
      'then and',
      'run',
    ]);
    expect(bdd.passed, [true]);
    expect(
      bdd.toString(),
      '  Scenario: after code\n'
      '    Given g\n'
      '      | a |\n'
      '      | 1 |\n'
      '    And g and\n'
      '    But g but\n'
      '    # G note\n'
      '    When w\n'
      '      | b |\n'
      '      | 2 |\n'
      '    And w and\n'
      '    And w and 2\n'
      '    But w but\n'
      '    # W note\n'
      '    Then t\n'
      '      | c |\n'
      '      | 3 |\n'
      '    And t and\n'
      '    # T note\n',
    );
  });

  test('every method after a code block, in other orders', () {
    final log = <String>[];

    final bdd = Bdd()
        .scenario('more after code')
        .given('g')
        .code((_) => log.add('given'))
        .note('g note')
        .then('t')
        .code((_) => log.add('then'))
        .but('t but')
        .code((_) => log.add('then but'))
        .note('t note')
        .testRun((_) => log.add('run'), _NoOpReporter());

    final bdd2 = Bdd()
        .scenario('given code to when')
        .given('g')
        .code((_) => log.add('given 2'))
        .but('g but')
        .code((_) => log.add('given but 2'))
        .when('w')
        .code((_) => log.add('when 2'))
        .note('w note')
        .then('t')
        .testRun((_) => log.add('run 2'), _NoOpReporter());

    final bdd3 = Bdd()
        .scenario('given code to then')
        .given('g')
        .code((_) => log.add('given 3'))
        .then('t')
        .testRun((_) => log.add('run 3'), _NoOpReporter());

    expect(log, [
      'given',
      'then',
      'then but',
      'run',
      'given 2',
      'given but 2',
      'when 2',
      'run 2',
      'given 3',
      'run 3',
    ]);
    expect(
        bdd3.toString(),
        '  Scenario: given code to then\n'
        '    Given g\n'
        '    Then t\n');
    expect(
      bdd.toString(),
      '  Scenario: more after code\n'
      '    Given g\n'
      '    # G note\n'
      '    Then t\n'
      '    But t but\n'
      '    # T note\n',
    );
    expect(
      bdd2.toString(),
      '  Scenario: given code to when\n'
      '    Given g\n'
      '    But g but\n'
      '    When w\n'
      '    # W note\n'
      '    Then t\n',
    );
  });

  test('every method after a table', () {
    final log = <String>[];

    final bdd = Bdd()
        .scenario('after tables')
        .given('g')
        .table('g1', row(val('a', 1)))
        .but('g but')
        .table('g2', row(val('a', 2)))
        .note('g note')
        .when('w')
        .table('w1', row(val('b', 1)))
        .but('w but')
        .table('w2', row(val('b', 2)))
        .note('w note')
        .and('w and')
        .table('w3', row(val('b', 3)))
        .then('t')
        .table('t1', row(val('c', 1)))
        .but('t but')
        .table('t2', row(val('c', 2)))
        .note('t note')
        .testRun((ctx) {
      log.add('run');
      for (final name in ['g1', 'g2', 'w1', 'w2', 'w3', 't1', 't2']) {
        expect(ctx.table(name).rows, hasLength(1), reason: name);
      }
    }, _NoOpReporter());

    expect(log, ['run']);
    expect(
      bdd.toString(),
      '  Scenario: after tables\n'
      '    Given g\n'
      '      | a |\n'
      '      | 1 |\n'
      '    But g but\n'
      '      | a |\n'
      '      | 2 |\n'
      '    # G note\n'
      '    When w\n'
      '      | b |\n'
      '      | 1 |\n'
      '    But w but\n'
      '      | b |\n'
      '      | 2 |\n'
      '    # W note\n'
      '    And w and\n'
      '      | b |\n'
      '      | 3 |\n'
      '    Then t\n'
      '      | c |\n'
      '      | 1 |\n'
      '    But t but\n'
      '      | c |\n'
      '      | 2 |\n'
      '    # T note\n',
    );
  });

  test('code blocks can follow tables', () {
    final log = <String>[];

    Bdd()
        .scenario('code after tables')
        .given('g')
        .table('g1', row(val('a', 1)))
        .code(
            (ctx) => log.add('given table ${ctx.table('g1').row(0).val('a')}'))
        .when('w')
        .table('w1', row(val('b', 2)))
        .code((ctx) => log.add('when table ${ctx.table('w1').row(0).val('b')}'))
        .then('t')
        .table('t1', row(val('c', 3)))
        .code((ctx) => log.add('then table ${ctx.table('t1').row(0).val('c')}'))
        .testRun((_) => log.add('run'), _NoOpReporter());

    expect(log, ['given table 1', 'when table 2', 'then table 3', 'run']);
  });

  test('a table holds up to four rows', () {
    final bdd = Bdd()
        .scenario('rows')
        .given('g')
        .table(
          'four rows',
          row(val('n', 1)),
          row(val('n', 2)),
          row(val('n', 3)),
          row(val('n', 4)),
        )
        .when('w')
        .then('t')
        .bdd;

    expect(bdd.tables().single.rows, hasLength(4));
  });

  test('timeoutSec() passes the timeout to the test', () {
    final invocations = <TestInvocation>[];
    final bdd = Bdd().scenario('slow').then('result').bdd.timeoutSec(42);

    BddRunner().run(bdd, (_) {}, invocations.add, null);

    expect(invocations.single.timeout, const Timeout(Duration(seconds: 42)));
  });

  test('TestResult exposes the rendered lines and the skip flag', () {
    final reporter = _NoOpReporter();
    BddReporter.set(reporter);
    final feature = BddFeature('results');

    final run = Bdd(feature).scenario('run').given('g').when('w').then('t').bdd;
    final skipped = Bdd(feature).scenario('skipped').then('t').bdd.skip;
    for (final bdd in [run, skipped]) {
      BddRunner().run(bdd, (_) {}, (_) {}, null);
    }

    final results = reporter.features.single.testResults;
    expect(results.map((result) => result.toMap()), [
      ['  Scenario: run', '    Given g', '    When w', '    Then t'],
      ['  Scenario: skipped', '    Then t'],
    ]);
    expect(results.map((result) => result.wasSkipped), [false, true]);
    expect(
      results.first.toMap(const BddConfig(indent: 1, padChar: '.')),
      ['.Scenario: run', '..Given g', '..When w', '..Then t'],
    );
  });
}

class _NoOpReporter extends BddReporter {
  @override
  Future<void> report() async {}
}

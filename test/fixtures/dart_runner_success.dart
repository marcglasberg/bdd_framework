import 'package:bdd_framework/dart_test.dart';
import 'package:test/test.dart';

void main() {
  final events = <String>[];
  final feature = BddFeature('entry points');
  final when = Bdd(feature);
  final then = Bdd(feature);
  final skipped = Bdd(feature).skip;
  BddReporter.set(_ResultReporter());
  setUpAll(() => events.add('setupAll'));
  setUp(() => events.add('setup'));
  tearDown(() => events.add('teardown'));
  feature.background.given('shared setup').code((_) async {
    await Future<void>.delayed(Duration.zero);
    events.add('background');
  });
  when
      .scenario('When success')
      .when('action')
      .code((_) async {
        await Future<void>.delayed(Duration.zero);
        events.add('when');
      })
      .then('outcome')
      .code((_) => events.add('then'))
      .run((_) {
        events.add('callback');
      });
  then
      .scenario('Then success')
      .then('outcome')
      .code((_) => events.add('then'))
      .and('also')
      .code((_) => events.add('and'))
      .but('except')
      .code((_) => events.add('but'))
      .run();
  skipped
      .scenario('skip failure')
      .then('never execute')
      .run((_) => fail('unexpected skipped code'));
  tearDownAll(() {
    expect(events, [
      'setupAll',
      'setup',
      'background',
      'when',
      'then',
      'callback',
      'teardown',
      'setup',
      'background',
      'then',
      'and',
      'but',
      'teardown'
    ]);
    expect(when.passed, [true]);
    expect(then.passed, [true]);
    expect(skipped.passed, isEmpty);
    expect(BddReporter.runInfo.passedCount, 2);
    expect(BddReporter.runInfo.failedCount, 0);
    expect(BddReporter.runInfo.skipCount, 1);
  });
  BddReporter.reportAll();
}

class _ResultReporter extends BddReporter {
  @override
  Future<void> report() async {
    expect(features.single.testResults.length, 3);
    print('fixture reporter completed');
  }
}

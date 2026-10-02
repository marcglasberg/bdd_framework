import 'dart:io';

import 'package:bdd_framework/dart_test.dart';
import 'package:test/test.dart';

void main() {
  test('reports shared Background once for When/Then entry scenarios',
      () async {
    final directory = await Directory.systemTemp.createTemp('bdd-report-test-');
    final previousDirectory = FeatureFileReporter.dir;
    addTearDown(() async {
      BddReporter.set();
      FeatureFileReporter.dir = previousDirectory;
      await directory.delete(recursive: true);
    });
    FeatureFileReporter.dir = directory.path;
    final reporter = FeatureFileReporter();
    BddReporter.set(reporter);
    final feature = BddFeature('entry points');
    feature.background.given('shared setup');
    final when = Bdd(feature);
    when.scenario('When flow').when('action').then('result');
    final then = Bdd(feature);
    then.scenario('Then flow').then('result');
    for (final bdd in [when, then]) {
      final invocations = <TestInvocation>[];
      BddRunner().run(bdd, (_) {}, invocations.add, null, () => true);
      await invocations.single.body();
    }
    await reporter.report();
    final output =
        await File('${directory.path}/entry_points.feature').readAsString();
    expect(
        output,
        'Feature: entry points\n\n'
        '  Background:\n    Given shared setup\n\n'
        '  Scenario: When flow\n    When action\n    Then result\n\n'
        '  Scenario: Then flow\n    Then result\n');
    expect(
        reporter.features.single.testResults.map((result) => result.passed), [
      [true],
      [true]
    ]);
  });

  test('clearAllOutputBeforeRun deletes only the feature files in dir',
      () async {
    final directory = await Directory.systemTemp.createTemp('bdd-report-test-');
    final previousDirectory = FeatureFileReporter.dir;
    addTearDown(() async {
      BddReporter.set();
      FeatureFileReporter.dir = previousDirectory;
      await directory.delete(recursive: true);
    });
    final oldFeature = File('${directory.path}/old.feature')
      ..writeAsStringSync('Feature: old');
    final otherFile = File('${directory.path}/notes.txt')
      ..writeAsStringSync('keep');
    final nestedFeature = File('${directory.path}/sub/nested.feature')
      ..createSync(recursive: true)
      ..writeAsStringSync('keep');
    FeatureFileReporter.dir = directory.path;
    final reporter = FeatureFileReporter(clearAllOutputBeforeRun: true);
    BddReporter.set(reporter);
    final bdd = Bdd(BddFeature('new'));
    bdd.scenario('flow').then('result');
    final invocations = <TestInvocation>[];
    BddRunner().run(bdd, (_) {}, invocations.add, null, () => true);
    await invocations.single.body();
    await reporter.report();
    expect(oldFeature.existsSync(), isFalse);
    expect(otherFile.readAsStringSync(), 'keep');
    expect(nestedFeature.readAsStringSync(), 'keep');
    expect(File('${directory.path}/new.feature').existsSync(), isTrue);
  });

  test('an empty dir means the current directory, not the filesystem root',
      () {
    final previousDirectory = FeatureFileReporter.dir;
    addTearDown(() => FeatureFileReporter.dir = previousDirectory);
    FeatureFileReporter.dir = '';
    expect(FeatureFileReporter().directory, './');
  });
}

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
}

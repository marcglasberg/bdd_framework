import 'dart:io';

import 'package:bdd_framework/dart_test.dart';
import 'package:test/test.dart';

/// Writes Cucumber Messages to the file in the `BDD_MESSAGES_PATH`
/// environment variable, from a real `package:test` run.
void main() {
  BddReporter.set(
      MessagesReporter(path: Platform.environment['BDD_MESSAGES_PATH']!));

  final feature = BddFeature('Messages from a real run');
  feature.background.given('a background').code((_) {});

  Bdd(feature)
      .scenario('Passing')
      .given('a step')
      .code((_) => Future<void>.delayed(const Duration(milliseconds: 20)))
      .then('a step without code')
      .run();

  Bdd(feature)
      .scenario('Failing')
      .given('a failing step')
      .code((_) => expect(1, 2))
      .then('a skipped step')
      .run();

  Bdd(feature)
      .scenario('Outline <n>')
      .given('the number <n>')
      .then('it is small')
      .example(val('n', 1))
      .example(val('n', 1000))
      .run((ctx) => expect(ctx.example.val('n') as int, lessThan(10)));

  Bdd(feature).skip.scenario('Skipped').then('never runs').run();

  BddReporter.reportAll();
}

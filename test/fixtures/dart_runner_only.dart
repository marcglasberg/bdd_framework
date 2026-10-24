// Launched by dart_test_runner_process_test.dart.
// Some tests are marked with `.only`, so only those run, and the others
// are skipped. This file does not end in _test.dart, so normal test
// discovery excludes it.
// ignore_for_file: invalid_use_of_do_not_submit_member
import 'package:bdd_framework/dart_test.dart';
import 'package:test/test.dart';

void main() {
  final feature = BddFeature('only');

  Bdd(feature)
      .scenario('not marked')
      .then('is skipped')
      .run((_) => fail('unexpected run: not marked'));

  Bdd(feature)
      .only
      .scenario('marked with examples')
      .then('runs <n>')
      .example(val('n', 1))
      .example(val('n', 2))
      .run();

  group('a group', () {
    Bdd(feature).only.scenario('marked in a group').then('runs').run();

    Bdd(feature)
        .scenario('not marked in a group')
        .then('is skipped')
        .run((_) => fail('unexpected run: not marked in a group'));
  });
}

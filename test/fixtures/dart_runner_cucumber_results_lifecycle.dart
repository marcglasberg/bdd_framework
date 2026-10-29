// Synthetic lifecycle cases launched by cucumber_results_reporter_lifecycle_process_test.
// Intentionally failing cases are excluded from normal test discovery.
import 'dart:async';
import 'dart:io';

import 'package:bdd_framework/dart_test.dart';
import 'package:test/test.dart';

void main() {
  final mode = Platform.environment['BDD_RESULTS_CASE']!;
  if (!const {
    'passing',
    'body-failure',
    'setup',
    'teardown',
    'timeout',
    'late-teardown-all',
    'retry',
    'missing-scenario',
    'abrupt-exit',
  }.contains(mode)) {
    throw ArgumentError('Unknown lifecycle fixture: $mode');
  }

  BddReporter.set(
    CucumberResultsReporter(path: Platform.environment['BDD_RESULTS_PATH']!),
  );
  if (mode == 'setup') {
    setUp(() => throw StateError('synthetic setup failure'));
  } else if (mode == 'teardown') {
    tearDown(() => throw StateError('synthetic teardown failure'));
  }

  final bdd = Bdd(BddFeature('Lifecycle: $mode'));
  if (mode == 'missing-scenario') {
    bdd.given('no scenario was declared').then('the body passes').run();
  } else if (mode == 'retry') {
    final scenario = bdd
        .scenario('recovers on retry')
        .then('synthetic check')
        .bdd;
    var attempts = 0;
    // The public delegate interface supplies package:test's retry option.
    BddRunner().run(
      scenario,
      (_) {
        if (++attempts == 1)
          throw StateError('synthetic first attempt failure');
      },
      (invocation) {
        test(invocation.description, invocation.body, retry: 1);
      },
      null,
      () => true,
    );
  } else {
    if (mode == 'timeout') bdd.timeout(const Duration(milliseconds: 30));
    bdd.scenario('body passes if it runs').then('synthetic check').run((
      _,
    ) async {
      if (mode == 'abrupt-exit') exit(23);
      if (mode == 'body-failure') throw StateError('synthetic body failure');
      if (mode == 'timeout') {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(1, 1);
    });
  }

  if (mode == 'timeout') {
    // The timed-out future can finish while a subsequent test is running.
    test('remaining ordinary work', () async {
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
  }
  if (mode == 'late-teardown-all') {
    // Registered first so the failure occurs after the reporter's teardown.
    tearDownAll(() => throw StateError('synthetic late teardown-all failure'));
  }
  BddReporter.reportAll();
}

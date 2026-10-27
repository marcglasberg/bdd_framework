// Synthetic lifecycle cases launched by messages_reporter_lifecycle_process_test.
// Intentionally failing cases are excluded from normal test discovery.
import 'dart:async';
import 'dart:io';

import 'package:bdd_framework/dart_test.dart';
import 'package:test/test.dart';

void main() {
  final mode = Platform.environment['BDD_MESSAGES_CASE']!;
  if (!const {
    'passing',
    'setup',
    'teardown',
    'timeout',
    'late-teardown-all',
    'missing-scenario',
  }.contains(mode)) {
    throw ArgumentError('Unknown lifecycle fixture: $mode');
  }

  BddReporter.set(
    MessagesReporter(path: Platform.environment['BDD_MESSAGES_PATH']!),
  );
  if (mode == 'setup') {
    setUp(() => throw StateError('synthetic setup failure'));
  } else if (mode == 'teardown') {
    tearDown(() => throw StateError('synthetic teardown failure'));
  }

  final bdd = Bdd(BddFeature('Lifecycle: $mode'));
  if (mode == 'missing-scenario') {
    bdd.given('no scenario was declared').then('the body passes').run();
  } else {
    if (mode == 'timeout') {
      bdd.timeout(const Duration(milliseconds: 30));
    }
    bdd.scenario('body passes if it runs').then('synthetic check').run((
      _,
    ) async {
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
    // tearDownAll callbacks run in reverse registration order. This failure
    // therefore happens after the reporter has written its result.
    tearDownAll(() => throw StateError('synthetic late teardown-all failure'));
  }
  BddReporter.reportAll();
}

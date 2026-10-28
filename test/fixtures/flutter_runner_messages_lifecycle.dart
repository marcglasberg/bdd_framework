// Real Flutter runner cases for two-stage MessagesReporter finalization.
// This fixture is launched explicitly and excluded from normal discovery.
import 'dart:io';

import 'package:bdd_framework/flutter_test.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final mode = Platform.environment['BDD_MESSAGES_CASE']!;
  if (mode != 'passing' && mode != 'teardown') {
    throw ArgumentError('Unknown Flutter lifecycle fixture: $mode');
  }
  BddReporter.set(
    MessagesReporter(path: Platform.environment['BDD_MESSAGES_PATH']!),
  );
  if (mode == 'teardown') {
    tearDown(() => throw StateError('synthetic Flutter teardown failure'));
  }
  Bdd(
    BddFeature('Flutter lifecycle: $mode'),
  ).scenario('body passes').then('synthetic check').run((_) => expect(1, 1));
  BddReporter.reportAll();
}

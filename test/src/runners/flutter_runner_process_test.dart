// Runs the intentionally failing Flutter fixtures in a separate `flutter test`
// process, since a failing test can't be observed from inside the same run.
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('Flutter runner failures fail the test and are reported cleanly',
      () async {
    final result = await _runFlutterFixture('flutter_runner_failures.dart');
    final events = _events(result);
    final output = _printed(events);

    expect(result.exitCode, isNot(0), reason: '${result.stdout}');
    expect(events.last['success'], isFalse);
    expect(_results(events), ['error', 'error']);
    expect(
        'EXCEPTION CAUGHT BY BDD FRAMEWORK'.allMatches(output), hasLength(2));
    expect(output, contains('expected Flutter assertion failure'));
    expect(output, contains('Bad state: expected Flutter async failure'));
    expect(output, contains('TEST 1 FAILED!'));
    expect(output, contains('TEST 2 FAILED!'));
    _expectFilteredStack(output);
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('Flutter widget runner failures fail the test and are reported cleanly',
      () async {
    final result =
        await _runFlutterFixture('flutter_widget_runner_failures.dart');
    final events = _events(result);
    final output = _printed(events);

    expect(result.exitCode, isNot(0), reason: '${result.stdout}');
    expect(events.last['success'], isFalse);
    expect(_results(events), ['error', 'error', 'error', 'error']);
    expect(output, contains('expected widget step failure'));
    // With BddFlutter.ignoreOverflow on, other Flutter errors still fail.
    expect(output, contains('expected non-overflow Flutter error'));
    expect(output, isNot(contains('unexpected later code')));
    expect(output, contains('Bad state: expected widget async failure'));
    // With BddFlutter.ignoreOverflow off, an overflow fails the test.
    expect(output, contains('A RenderFlex overflowed by'));
    // Errors Flutter reports without throwing, like an overflow, still make
    // the BDD print FAILED, and stop the steps after them.
    for (final test in [1, 2, 3, 4]) {
      expect(output, contains('TEST $test FAILED!'));
    }
    expect(output, isNot(contains('PASSED!')));
    // The original error is shown once, with its details, not twice.
    expect('EXCEPTION CAUGHT BY RENDERING LIBRARY'.allMatches(output),
        hasLength(1));
    expect(output, contains('The relevant error-causing widget was'));
    _expectFilteredStack(output);
  }, timeout: const Timeout(Duration(minutes: 3)));

  for (final runner in ['flutter_runner', 'flutter_widget_runner']) {
    test('.only runs only the marked tests, and skips the others ($runner)',
        () async {
      final result = await _runFlutterFixture('${runner}_only.dart');
      final events = _events(result);

      expect(result.exitCode, 0, reason: '${result.stdout}');
      expect(_ranOrSkipped(events), _onlyExpected);
      expect(_printed(events), isNot(contains('unexpected run')));
    }, timeout: const Timeout(Duration(minutes: 3)));
  }
}

/// The runners filter their own frames, and the matcher's, out of the stack.
void _expectFilteredStack(String output) {
  final frames = output
      .split('\n')
      .where((line) => RegExp(r'^#\d+ ').hasMatch(line))
      .toList();
  expect(frames, isNotEmpty);
  expect(frames, everyElement(isNot(contains('package:bdd_framework/src/'))));
  expect(frames, everyElement(isNot(contains('package:matcher/'))));
}

Future<ProcessResult> _runFlutterFixture(String name) => Process.run(
      _flutterExecutable(),
      [
        'test',
        '--no-pub',
        '--reporter=json',
        'test/fixtures/$name',
      ],
      runInShell: Platform.isWindows,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );

String _flutterExecutable() {
  // Flutter tests run in flutter_tester, inside the Flutter SDK's bin/cache.
  final flutterRoot = Platform.environment['FLUTTER_ROOT'] ??
      File(Platform.resolvedExecutable)
          .parent
          .parent
          .parent
          .parent
          .parent
          .parent
          .path;
  final flutter =
      File('$flutterRoot/bin/flutter${Platform.isWindows ? '.bat' : ''}');
  if (!flutter.existsSync())
    throw StateError('Flutter executable not found: ${flutter.path}');
  return flutter.path;
}

List<Map<String, dynamic>> _events(ProcessResult result) => const LineSplitter()
    .convert(result.stdout as String)
    .where((line) => line.trimLeft().startsWith('{'))
    .map((line) => jsonDecode(line) as Map<String, dynamic>)
    .toList();

/// The result of each visible test, in order.
List<String> _results(List<Map<String, dynamic>> events) => [
      for (final event in events)
        if (event['type'] == 'testDone' && event['hidden'] != true)
          event['result'] as String,
    ];

/// Everything the tests printed, without ANSI colors.
String _printed(List<Map<String, dynamic>> events) => [
      for (final event in events)
        if (event['type'] == 'print') event['message'] as String,
    ].join('\n').replaceAll(RegExp(r'\x1B\[[0-9;]*m'), '');

/// Each visible test's name and whether it was skipped, as "name: ran" or
/// "name: skipped". Names are trimmed, since a test marked with `.only` in a
/// Flutter runner is declared inside a group with an empty name.
List<String> _ranOrSkipped(List<Map<String, dynamic>> events) {
  final names = <int, String>{
    for (final event in events)
      if (event['type'] == 'testStart')
        (event['test'] as Map)['id'] as int:
            ((event['test'] as Map)['name'] as String)
                .replaceAll(RegExp(r'\s+'), ' ')
                .trim(),
  };
  return [
    for (final event in events)
      if (event['type'] == 'testDone' && event['hidden'] != true)
        '${names[event['testID']]}: '
            '${event['skipped'] == true ? 'skipped' : 'ran'}',
  ];
}

/// What every `*_runner_only.dart` fixture should produce.
const _onlyExpected = [
  '1 not marked: skipped',
  '2₁ marked with examples: ran',
  '2₂ marked with examples: ran',
  'a group 3 marked in a group: ran',
  'a group 4 not marked in a group: skipped',
];

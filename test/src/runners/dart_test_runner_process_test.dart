import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('Dart step, background, callback and example failures fail the process',
      () async {
    final result = await _runFixture('dart_runner_failures.dart');
    final events = _events(result);
    expect(result.exitCode, isNot(0), reason: result.stdout.toString());
    expect(events, isNotEmpty, reason: result.stderr.toString());
    expect(events.last['success'], isFalse);
    final completed = events
        .where(
            (event) => event['type'] == 'testDone' && event['hidden'] != true)
        .toList();
    expect(completed.where((event) => event['result'] != 'success'),
        hasLength(13));
    expect(
        completed.where((event) => event['result'] == 'success'), hasLength(1));
    expect(result.stdout, contains('fixture reporter completed'));
    expect(result.stdout, isNot(contains('unexpected later code')));
    // BddReporter.reportAll() prints a summary before running the reporters.
    expect(
        result.stdout,
        stringContainsInOrder([
          'RESULTS',
          'TOTAL: 14 tests (13 BDDs)',
          'PASSED: 1 tests',
          'FAILED: 13 tests',
          'SKIPPED: 0 tests',
          'Running the _ResultReporter...',
          'fixture reporter completed',
        ]));
    expect(
        events.where((event) =>
            event['type'] == 'print' &&
            event['message'].toString().contains('fixture teardown completed')),
        hasLength(14));
    for (final keyword in ['When', 'Then']) {
      for (final mode in ['sync', 'async']) {
        for (final location in ['step', 'background', 'callback']) {
          expect(result.stdout,
              contains('expected failure: $keyword $mode $location failure'));
        }
      }
    }
  }, timeout: const Timeout(Duration(minutes: 2)));

  test(
      'Dart When/Then successes and skip preserve lifecycle and process status',
      () async {
    final result = await _runFixture('dart_runner_success.dart');
    final events = _events(result);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    expect(events.last['success'], isTrue);
    final completed = events
        .where(
            (event) => event['type'] == 'testDone' && event['hidden'] != true)
        .toList();
    expect(completed, hasLength(3));
    expect(completed.where((event) => event['skipped'] == true), hasLength(1));
    expect(result.stdout, contains('fixture reporter completed'));
    expect(result.stdout, isNot(contains('unexpected skipped code')));
    expect(
        result.stdout,
        stringContainsInOrder([
          'RESULTS',
          'TOTAL: 3 tests (3 BDDs)',
          'PASSED: 2 tests',
          'FAILED: 0 tests',
          'SKIPPED: 1 tests',
          'Running the _ResultReporter...',
          'fixture reporter completed',
        ]));
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('MessagesReporter writes partial results of a real run', () async {
    final temporary = await Directory.systemTemp.createTemp('bdd-messages-');
    final directory = Directory(await temporary.resolveSymbolicLinks());
    addTearDown(() => directory.delete(recursive: true));
    final path = '${directory.path}/messages.ndjson';

    final result = await _runFixture('dart_runner_messages.dart',
        environment: {'BDD_MESSAGES_PATH': path});
    expect(result.stdout, contains('Partial Cucumber Messages saved in $path.partial'));
    expect(result.exitCode, isNot(0));
    expect(File(path).existsSync(), isFalse);

    final envelopes = File('$path.partial')
        .readAsLinesSync()
        .map((line) => jsonDecode(line) as Map<String, dynamic>)
        .toList();
    Iterable<Map<String, dynamic>> all(String type) => envelopes
        .where((envelope) => envelope.containsKey(type))
        .map((envelope) => envelope[type] as Map<String, dynamic>);

    final pickleNames = {
      for (final pickle in all('pickle')) pickle['id']: pickle['name'],
    };
    final pickleOfTestCase = {
      for (final testCase in all('testCase'))
        testCase['id']: pickleNames[testCase['pickleId']],
    };
    final statuses = <String, List<String>>{};
    final testCaseOfStarted = <Object?, Object?>{};
    for (final started in all('testCaseStarted')) {
      testCaseOfStarted[started['id']] = started['testCaseId'];
    }
    for (final finished in all('testStepFinished')) {
      final name = pickleOfTestCase[
          testCaseOfStarted[finished['testCaseStartedId']]] as String;
      final result = finished['testStepResult'] as Map<String, dynamic>;
      (statuses[name] ??= []).add(result['status'] as String);
    }

    expect(statuses, {
      'Passing': ['PASSED', 'PASSED', 'PASSED', 'PASSED'],
      'Failing': ['PASSED', 'FAILED', 'SKIPPED', 'SKIPPED'],
      'Outline 1': ['PASSED', 'PASSED', 'PASSED', 'PASSED'],
      'Outline 1000': ['PASSED', 'PASSED', 'PASSED', 'FAILED'],
      'Skipped': ['SKIPPED', 'SKIPPED', 'SKIPPED'],
    });
    expect(all('testRunFinished'), isEmpty);
    const markerPrefix = 'bdd_framework.messages.v1:';
    final events = _events(result);
    final markerEvent = events.singleWhere((event) =>
        event['type'] == 'print' &&
        event['message'].toString().startsWith(markerPrefix));
    final marker = jsonDecode((markerEvent['message'] as String)
        .substring(markerPrefix.length)) as Map<String, dynamic>;
    expect(marker['id'], all('testRunStarted').single['id']);
    final uri = File(path).absolute.uri.normalizePath().toString();
    expect(marker['output'], Platform.isWindows ? uri.toLowerCase() : uri);
    expect(events.last['type'], 'done');
    expect(events.last['success'], isFalse);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('.only runs only the marked tests, and skips the others', () async {
    final result = await _runFixture('dart_runner_only.dart');
    final events = _events(result);

    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    expect(_ranOrSkipped(events), _onlyExpected);
    expect(result.stdout, isNot(contains('unexpected run')));
  }, timeout: const Timeout(Duration(minutes: 2)));
}

Future<ProcessResult> _runFixture(
  String name, {
  Map<String, String> environment = const {},
}) async {
  final configFile = File('.dart_tool/package_config.json').absolute;
  final config =
      jsonDecode(await configFile.readAsString()) as Map<String, dynamic>;
  final packages = config['packages'] as List<dynamic>;
  final testPackage = packages
      .cast<Map<String, dynamic>>()
      .singleWhere((package) => package['name'] == 'test');
  final rootUri = testPackage['rootUri'] as String;
  final testRoot =
      configFile.uri.resolve(rootUri.endsWith('/') ? rootUri : '$rootUri/');
  final testRunner = testRoot.resolve('bin/test.dart').toFilePath();
  return Process.run(
    _dartExecutable(),
    [
      '--packages=${configFile.path}',
      testRunner,
      '--reporter=json',
      '--concurrency=1',
      'test/fixtures/$name'
    ],
    environment: {'DART_SUPPRESS_ANALYTICS': 'true', ...environment},
    stdoutEncoding: utf8,
    stderrEncoding: utf8,
  );
}

String _dartExecutable() {
  final executable = File(Platform.resolvedExecutable);
  final name = Platform.isWindows ? 'dart.exe' : 'dart';
  if (executable.uri.pathSegments.last == name) return executable.path;
  // Flutter tests run in flutter_tester, rather than in the Dart CLI.
  final flutterRoot = Platform.environment['FLUTTER_ROOT'] ??
      executable.parent.parent.parent.parent.parent.parent.path;
  final dart = File('$flutterRoot/bin/cache/dart-sdk/bin/$name');
  if (!dart.existsSync())
    throw StateError('Dart SDK executable not found: ${dart.path}');
  return dart.path;
}

List<Map<String, dynamic>> _events(ProcessResult result) => const LineSplitter()
    .convert(result.stdout as String)
    .where((line) => line.trimLeft().startsWith('{'))
    .map((line) => jsonDecode(line) as Map<String, dynamic>)
    .toList();

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

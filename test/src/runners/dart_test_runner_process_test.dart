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
  }, timeout: const Timeout(Duration(minutes: 2)));
}

Future<ProcessResult> _runFixture(String name) async {
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
    environment: {'DART_SUPPRESS_ANALYTICS': 'true'},
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

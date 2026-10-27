import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  for (final mode in [
    'passing',
    'setup',
    'teardown',
    'timeout',
    'late-teardown-all',
  ]) {
    test('MessagesReporter does not claim suite success: $mode', () async {
      final temporary = await Directory.systemTemp.createTemp('bdd-lifecycle-');
      final directory = Directory(await temporary.resolveSymbolicLinks());
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/messages.ndjson');

      final result = await _runFixture(mode, file.path);
      final events = _events(result);
      final passing = mode == 'passing';
      expect(
        result.exitCode,
        passing ? 0 : 1,
        reason: '${result.stdout}\n${result.stderr}',
      );
      expect(events.last['success'], passing);

      final envelopes = file
          .readAsLinesSync()
          .map((line) => jsonDecode(line) as Map<String, dynamic>)
          .toList();
      final finished = envelopes.singleWhere(
        (envelope) => envelope.containsKey('testRunFinished'),
      );
      final run = finished['testRunFinished'] as Map<String, dynamic>;
      expect(run['success'], isFalse);
      expect(run['message'], contains('Incomplete'));
      expect(run['message'], contains('final runner result unavailable'));

      // Detailed BDD observations remain available even though the framework
      // cannot establish the final result of the surrounding test suite.
      final statuses = envelopes
          .where((envelope) => envelope.containsKey('testStepFinished'))
          .map(
            (envelope) =>
                (envelope['testStepFinished']
                    as Map)['testStepResult']['status'],
          )
          .toList();
      expect(statuses, isNotEmpty);
      expect(statuses, everyElement(mode == 'setup' ? 'SKIPPED' : 'PASSED'));

      if (mode == 'late-teardown-all') {
        final output = result.stdout as String;
        final written = output.indexOf('Cucumber Messages saved in');
        final failed = output.indexOf('synthetic late teardown-all failure');
        expect(written, greaterThanOrEqualTo(0));
        expect(failed, greaterThan(written));
      }
    }, timeout: const Timeout(Duration(minutes: 2)));
  }

  test(
    'missing scenario fails reporting and invalidates an older report',
    () async {
      final temporary = await Directory.systemTemp.createTemp('bdd-lifecycle-');
      final directory = Directory(await temporary.resolveSymbolicLinks());
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/messages.ndjson');
      const previous = '{"testRunFinished":{"success":true}}\n';
      await file.writeAsString(previous);

      final result = await _runFixture('missing-scenario', file.path);
      final events = _events(result);
      expect(result.exitCode, 1, reason: '${result.stdout}\n${result.stderr}');
      expect(events.last['success'], isFalse);
      expect(events.where((event) => event['type'] == 'error'), isNotEmpty);
      expect(result.stdout, isNot(contains('Cucumber Messages saved in')));
      expect(file.existsSync(), isFalse);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

Future<ProcessResult> _runFixture(String mode, String path) async {
  final configFile = File('.dart_tool/package_config.json').absolute;
  final config = jsonDecode(await configFile.readAsString()) as Map;
  final testPackage = (config['packages'] as List).cast<Map>().singleWhere(
    (package) => package['name'] == 'test',
  );
  final rootUri = testPackage['rootUri'] as String;
  final testRoot = configFile.uri.resolve(
    rootUri.endsWith('/') ? rootUri : '$rootUri/',
  );
  return Process.run(
    _dartExecutable(),
    [
      '--packages=${configFile.path}',
      testRoot.resolve('bin/test.dart').toFilePath(),
      '--reporter=json',
      '--concurrency=1',
      'test/fixtures/dart_runner_messages_lifecycle.dart',
    ],
    environment: {
      'DART_SUPPRESS_ANALYTICS': 'true',
      'BDD_MESSAGES_CASE': mode,
      'BDD_MESSAGES_PATH': path,
    },
    stdoutEncoding: utf8,
    stderrEncoding: utf8,
  );
}

String _dartExecutable() {
  final executable = File(Platform.resolvedExecutable);
  final name = Platform.isWindows ? 'dart.exe' : 'dart';
  if (executable.uri.pathSegments.last == name) return executable.path;
  final flutterRoot =
      Platform.environment['FLUTTER_ROOT'] ??
      executable.parent.parent.parent.parent.parent.parent.path;
  final dart = File('$flutterRoot/bin/cache/dart-sdk/bin/$name');
  if (!dart.existsSync()) {
    throw StateError('Dart SDK executable not found: ${dart.path}');
  }
  return dart.path;
}

List<Map<String, dynamic>> _events(ProcessResult result) => const LineSplitter()
    .convert(result.stdout as String)
    .where((line) => line.trimLeft().startsWith('{'))
    .map((line) => jsonDecode(line) as Map<String, dynamic>)
    .toList();

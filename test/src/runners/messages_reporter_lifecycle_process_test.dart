import 'dart:convert';
import 'dart:io';

import 'package:bdd_framework/messages.dart';
import 'package:test/test.dart';

const _markerPrefix = 'bdd_framework.messages.v1:';

void main() {
  for (final flutter in [false, true]) {
    final modes = flutter
        ? ['passing', 'teardown']
        : [
            'passing',
            'body-failure',
            'setup',
            'teardown',
            'timeout',
            'late-teardown-all',
            'retry',
          ];
    for (final mode in modes) {
      test(
        'finalizes the real ${flutter ? 'Flutter' : 'Dart'} runner: $mode',
        () async {
          final directory = await _temporaryDirectory();
          addTearDown(() => directory.delete(recursive: true));
          final file = File('${directory.path}/messages.ndjson');
          final partial = File('${file.path}.partial');
          final runnerJson = File('${directory.path}/runner.json');
          file.writeAsStringSync('old report must not survive a new run');

          final result = await _runFixture(
            mode,
            file.path,
            runnerJson.path,
            flutter: flutter,
          );
          final events = _readJsonLines(runnerJson);
          final passing = mode == 'passing' || mode == 'retry';
          expect(
            result.exitCode,
            passing ? 0 : 1,
            reason: '${result.stdout}\n${result.stderr}',
          );
          expect(events.last['type'], 'done');
          expect(events.last['success'], passing);
          expect(file.existsSync(), isFalse);
          expect(partial.existsSync(), isTrue);

          final observed = _readJsonLines(partial);
          expect(
            observed.where((e) => e.containsKey('testRunFinished')),
            isEmpty,
          );
          final started = observed.singleWhere(
            (e) => e.containsKey('testRunStarted'),
          );
          final id = (started['testRunStarted'] as Map)['id'];
          expect(id, matches(RegExp(r'^[0-9a-f]{64}$')));
          final markers = events
              .where(
                (event) =>
                    event['type'] == 'print' &&
                    event['messageType'] == 'print' &&
                    event['message'] is String &&
                    (event['message'] as String).startsWith(_markerPrefix),
              )
              .toList();
          expect(markers, hasLength(1));
          final marker =
              jsonDecode(
                    (markers.single['message'] as String).substring(
                      _markerPrefix.length,
                    ),
                  )
                  as Map;
          expect(marker['id'], id);
          var output = file.absolute.uri.normalizePath().toString();
          if (Platform.isWindows) output = output.toLowerCase();
          expect(marker['output'], output);
          final markerTest = events.singleWhere(
            (event) =>
                event['type'] == 'testStart' &&
                (event['test'] as Map)['id'] == markers.single['testID'],
          );
          expect((markerTest['test'] as Map)['name'], '(tearDownAll)');

          final statuses = _stepStatuses(observed);
          expect(statuses, switch (mode) {
            'setup' => ['SKIPPED', 'SKIPPED'],
            'body-failure' => ['PASSED', 'FAILED'],
            'retry' => ['PASSED', 'FAILED', 'PASSED', 'PASSED'],
            _ => ['PASSED', 'PASSED'],
          });
          if (mode == 'retry') {
            // An earlier error is compatible with a successful final retry.
            expect(
              events.where((event) => event['type'] == 'error'),
              isNotEmpty,
            );
          }
          if (mode == 'late-teardown-all') {
            final failureIndex = events.indexWhere(
              (event) =>
                  event['type'] == 'error' &&
                  (event['error'] as String).contains(
                    'synthetic late teardown-all failure',
                  ),
            );
            expect(failureIndex, greaterThan(events.indexOf(markers.single)));
          }

          final success = await finalizeMessages(
            path: file.path,
            runnerJsonPath: runnerJson.path,
            testExitCode: result.exitCode,
          );
          expect(success, passing);
          expect(partial.existsSync(), isFalse);
          final finalized = _readJsonLines(file);
          final finished = finalized.where(
            (e) => e.containsKey('testRunFinished'),
          );
          expect(finished, hasLength(1));
          expect(
            (finished.single['testRunFinished'] as Map)['success'],
            passing,
          );
          expect(_stepStatuses(finalized), statuses);
        },
        timeout: const Timeout(Duration(minutes: 3)),
      );
    }
  }

  for (final mode in ['missing-scenario', 'abrupt-exit']) {
    test(
      '$mode cannot finalize an absent export or leave a previous report',
      () async {
        final directory = await _temporaryDirectory();
        addTearDown(() => directory.delete(recursive: true));
        final file = File('${directory.path}/messages.ndjson');
        final partial = File('${file.path}.partial');
        final runnerJson = File('${directory.path}/runner.json');
        file.writeAsStringSync('{"testRunFinished":{"success":true}}\n');

        final result = await _runFixture(mode, file.path, runnerJson.path);
        expect(
          result.exitCode,
          mode == 'abrupt-exit' ? 23 : 1,
          reason: '${result.stdout}\n${result.stderr}',
        );
        expect(partial.existsSync(), isFalse);
        if (mode == 'missing-scenario') {
          expect(file.existsSync(), isFalse);
          expect(_readJsonLines(runnerJson).last['success'], isFalse);
        } else if (runnerJson.existsSync()) {
          // Abrupt termination is allowed to truncate the JSON stream.
          expect(
            runnerJson.readAsStringSync(),
            isNot(contains('"type":"done"')),
          );
        }
        await expectLater(
          finalizeMessages(
            path: file.path,
            runnerJsonPath: runnerJson.path,
            testExitCode: result.exitCode,
          ),
          throwsA(anything),
        );
        expect(file.existsSync(), isFalse);
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );
  }
}

Future<Directory> _temporaryDirectory() async {
  final temporary = await Directory.systemTemp.createTemp('bdd-lifecycle-');
  return Directory(await temporary.resolveSymbolicLinks());
}

List<String> _stepStatuses(List<Map<String, dynamic>> envelopes) => envelopes
    .where((e) => e.containsKey('testStepFinished'))
    .map(
      (e) =>
          (e['testStepFinished'] as Map)['testStepResult']['status'] as String,
    )
    .toList();

List<Map<String, dynamic>> _readJsonLines(File file) => file
    .readAsLinesSync()
    .where((line) => line.trim().isNotEmpty)
    .map((line) => jsonDecode(line) as Map<String, dynamic>)
    .toList();

Future<ProcessResult> _runFixture(
  String mode,
  String path,
  String runnerJsonPath, {
  bool flutter = false,
}) async {
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
    flutter ? _flutterExecutable() : _dartExecutable(),
    [
      if (flutter) ...[
        '--no-version-check',
        'test',
        '--no-pub',
      ] else ...[
        '--packages=${configFile.path}',
        testRoot.resolve('bin/test.dart').toFilePath(),
      ],
      '--reporter=expanded',
      '--file-reporter=json:$runnerJsonPath',
      '--concurrency=1',
      'test/fixtures/${flutter ? 'flutter' : 'dart'}_runner_messages_lifecycle.dart',
    ],
    environment: {
      'DART_SUPPRESS_ANALYTICS': 'true',
      'FLUTTER_SUPPRESS_ANALYTICS': 'true',
      'CI': 'true',
      'BDD_MESSAGES_CASE': mode,
      'BDD_MESSAGES_PATH': path,
    },
    runInShell: flutter && Platform.isWindows,
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
  if (!dart.existsSync())
    throw StateError('Dart SDK executable not found: ${dart.path}');
  return dart.path;
}

String _flutterExecutable() {
  final flutterRoot =
      Platform.environment['FLUTTER_ROOT'] ??
      File(_dartExecutable()).parent.parent.parent.parent.parent.path;
  final flutter = File(
    '$flutterRoot/bin/flutter${Platform.isWindows ? '.bat' : ''}',
  );
  if (!flutter.existsSync())
    throw StateError('Flutter executable not found: ${flutter.path}');
  return flutter.path;
}

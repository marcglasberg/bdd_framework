import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bdd_framework/dart_test.dart';
import 'package:bdd_framework/messages.dart';
import 'package:test/test.dart';

void main() {
  late Directory directory;
  late File output;
  late File partial;
  late File runner;
  late MessagesReporter reporter;

  setUp(() async {
    final temporary = await Directory.systemTemp.createTemp('bdd-finalize-');
    directory = Directory(await temporary.resolveSymbolicLinks());
    output = File('${directory.path}/messages.ndjson');
    partial = File('${output.path}.partial');
    runner = File('${directory.path}/runner.json');
    reporter = MessagesReporter(path: output.path);
    BddReporter.set(reporter);
  });
  tearDown(() async {
    BddReporter.set();
    await directory.delete(recursive: true);
  });

  Future<void> prepare({bool bodyFails = false, bool result = true}) async {
    final bdd = Bdd(
      BddFeature('Finalization'),
    ).scenario('Keep results').then('an observed step').bdd;
    final invocations = <TestInvocation>[];
    BddRunner().run(
      bdd,
      (_) {
        if (bodyFails) throw StateError('synthetic failure');
      },
      invocations.add,
      (_, __) {},
    );
    await runZoned(
      invocations.single.body,
      zoneSpecification: ZoneSpecification(print: (_, __, ___, ____) {}),
    );
    await reporter.report();
    final envelopes = partial.readAsLinesSync().map(jsonDecode).cast<Map>();
    final id =
        envelopes.singleWhere(
              (e) => e.containsKey('testRunStarted'),
            )['testRunStarted']['id']
            as String;
    final uri = output.absolute.uri.normalizePath().toString();
    runner.writeAsStringSync(
      _runnerJson(id, Platform.isWindows ? uri.toLowerCase() : uri, result),
    );
  }

  Future<bool> finalize([int code = 0]) => finalizeMessages(
    path: output.path,
    runnerJsonPath: runner.path,
    testExitCode: code,
  );

  Future<ProcessResult> command(int code) => Process.run(
    _dartExecutable(),
    [
      '--packages=${File('.dart_tool/package_config.json').absolute.path}',
      'bin/finalize_messages.dart',
      '--messages=${output.path}',
      '--runner-json=${runner.path}',
      '--exit-code=$code',
    ],
    environment: {'DART_SUPPRESS_ANALYTICS': 'true'},
  );

  test('CLI preserves confirmed success with exit 0', () async {
    await prepare();
    final result = await command(0);
    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect(
      jsonDecode(output.readAsLinesSync().last)['testRunFinished']['success'],
      isTrue,
    );
    expect(partial.existsSync(), isFalse);
  });

  test('CLI preserves confirmed test failure with exit 1', () async {
    await prepare(bodyFails: true, result: false);
    final result = await command(1);
    expect(result.exitCode, 1, reason: '${result.stderr}');
    expect(
      jsonDecode(output.readAsLinesSync().last)['testRunFinished']['success'],
      isFalse,
    );
  });

  test(
    'CLI uses exit 2 for unknown outcome, without publishing false',
    () async {
      await prepare();
      final result = await command(130);
      expect(result.exitCode, 2);
      expect(result.stderr, contains('Unsupported test-runner exit code'));
      expect(output.existsSync(), isFalse);
      expect(partial.existsSync(), isFalse);
    },
  );

  test(
    'publishes true only after confirmation and preserves every BDD envelope',
    () async {
      await prepare();
      final original = partial.readAsStringSync();
      expect(output.existsSync(), isFalse);
      expect(await finalize(), isTrue);
      expect(partial.existsSync(), isFalse);
      final completed = output.readAsStringSync();
      expect(completed, startsWith(original));
      final finished = jsonDecode(
        output.readAsLinesSync().last,
      )['testRunFinished'];
      expect(finished['success'], isTrue);
      expect(
        finished['testRunStartedId'],
        jsonDecode(
          original
              .split('\n')
              .firstWhere((line) => line.startsWith('{"testRunStarted":')),
        )['testRunStarted']['id'],
      );
    },
  );

  test(
    'confirmed failure publishes false with complete body details',
    () async {
      await prepare(bodyFails: true, result: false);
      expect(await finalize(1), isFalse);
      expect(
        jsonDecode(output.readAsLinesSync().last)['testRunFinished']['success'],
        isFalse,
      );
      expect(output.readAsStringSync(), contains('synthetic failure'));
    },
  );

  test('runner success cannot hide a failing recorded final attempt', () async {
    await prepare(bodyFails: true);
    await expectLater(finalize(), throwsFormatException);
    expect(output.existsSync(), isFalse);
    expect(partial.existsSync(), isFalse);
  });

  test(
    'finalization is single-use and cannot resurrect the previous report',
    () async {
      await prepare();
      await finalize();
      await expectLater(finalize(), throwsA(isA<FileSystemException>()));
      expect(output.existsSync(), isFalse);
    },
  );

  test('old runner JSON cannot finalize a new partial', () async {
    await prepare();
    final oldLog = runner.readAsStringSync();
    await reporter.report();
    runner.writeAsStringSync(oldLog);
    output.writeAsStringSync('old final');
    await expectLater(finalize(), throwsFormatException);
    expect(output.existsSync(), isFalse);
    expect(partial.existsSync(), isFalse);
  });

  test(
    'unknown or interrupted outcome never becomes a false failure',
    () async {
      await prepare();
      runner.writeAsStringSync(
        runner.readAsStringSync().replaceAll(
          '"success":true',
          '"success":null',
        ),
      );
      await expectLater(finalize(130), throwsFormatException);
      expect(output.existsSync(), isFalse);
      expect(partial.existsSync(), isFalse);
    },
  );

  test(
    'missing log consumes the partial and removes stale final output',
    () async {
      await prepare();
      await runner.delete();
      output.writeAsStringSync('old final');
      await expectLater(finalize(), throwsA(isA<FileSystemException>()));
      expect(output.existsSync(), isFalse);
      expect(partial.existsSync(), isFalse);
    },
  );

  test(
    'truncated partial is rejected even with successful runner evidence',
    () async {
      await prepare();
      partial.writeAsStringSync(partial.readAsStringSync().trimRight());
      await expectLater(finalize(), throwsFormatException);
      expect(output.existsSync(), isFalse);
      expect(partial.existsSync(), isFalse);
    },
  );

  test('missing step result cannot silently disappear', () async {
    await prepare();
    final lines = partial.readAsLinesSync();
    lines.removeAt(
      lines.indexWhere((line) => line.contains('"testStepFinished"')),
    );
    partial.writeAsStringSync('${lines.join('\n')}\n');
    await expectLater(finalize(), throwsFormatException);
    expect(output.existsSync(), isFalse);
  });

  test('a complete JSON prefix cannot drop all planned cases', () async {
    await prepare();
    final lines = partial.readAsLinesSync();
    final index = lines.indexWhere(
      (line) => line.contains('"testRunStarted":'),
    );
    partial.writeAsStringSync('${lines.take(index + 1).join('\n')}\n');
    await expectLater(finalize(), throwsFormatException);
    expect(output.existsSync(), isFalse);
  });

  test(
    'malformed partial diagnostics do not copy sensitive source text',
    () async {
      await prepare();
      const secret = 'synthetic-sensitive-sentinel';
      partial.writeAsStringSync('{"source":"$secret", broken}\n');
      await expectLater(
        finalize(),
        throwsA(
          isA<FormatException>().having(
            (error) => error.toString(),
            'diagnostic',
            isNot(contains(secret)),
          ),
        ),
      );
      expect(output.existsSync(), isFalse);
    },
  );

  test(
    'unknown test-case references cannot create a successful report',
    () async {
      await prepare();
      final lines = partial
          .readAsLinesSync()
          .map(jsonDecode)
          .cast<Map>()
          .toList();
      lines.singleWhere(
        (e) => e.containsKey('testCaseStarted'),
      )['testCaseStarted']['testCaseId'] = 'unknown';
      partial.writeAsStringSync('${lines.map(jsonEncode).join('\n')}\n');
      await expectLater(finalize(), throwsFormatException);
      expect(output.existsSync(), isFalse);
    },
  );

  test('a finalized envelope cannot be supplied as an intermediate', () async {
    await prepare();
    await finalize();
    output.copySync(partial.path);
    await expectLater(finalize(), throwsFormatException);
    expect(output.existsSync(), isFalse);
  });

  test('input alias is rejected before removing any data', () async {
    await prepare();
    await expectLater(
      finalizeMessages(
        path: output.path,
        runnerJsonPath: '${directory.path}/./messages.ndjson.partial',
        testExitCode: 0,
      ),
      throwsArgumentError,
    );
    expect(partial.existsSync(), isTrue);
    expect(runner.existsSync(), isTrue);
  });

  test(
    'a runner symlink to the output is rejected before removing its target',
    () async {
      await prepare();
      output.writeAsStringSync('synthetic existing output');
      await runner.delete();
      await Link(runner.path).create(output.path);
      await expectLater(finalize(), throwsA(isA<FileSystemException>()));
      expect(output.readAsStringSync(), 'synthetic existing output');
      expect(partial.existsSync(), isTrue);
    },
  );
}

String _dartExecutable() {
  final executable = File(Platform.resolvedExecutable);
  final name = Platform.isWindows ? 'dart.exe' : 'dart';
  if (executable.uri.pathSegments.last == name) return executable.path;
  final flutterRoot =
      Platform.environment['FLUTTER_ROOT'] ??
      executable.parent.parent.parent.parent.parent.parent.path;
  return '$flutterRoot/bin/cache/dart-sdk/bin/$name';
}

String _runnerJson(String id, String output, bool success) =>
    [
      {'type': 'start', 'time': 0, 'protocolVersion': '0.1.1', 'pid': 1},
      {
        'type': 'suite',
        'time': 1,
        'suite': {'id': 0, 'platform': 'vm', 'path': 'test.dart'},
      },
      {
        'type': 'testStart',
        'time': 2,
        'test': {'id': 1, 'suiteID': 0, 'name': '(tearDownAll)'},
      },
      {
        'type': 'print',
        'time': 3,
        'testID': 1,
        'messageType': 'print',
        'message':
            'bdd_framework.messages.v1:${jsonEncode({'id': id, 'output': output})}',
      },
      {
        'type': 'testDone',
        'time': 4,
        'testID': 1,
        'hidden': true,
        'skipped': false,
        'result': 'success',
      },
      {'type': 'done', 'time': 5, 'success': success},
    ].map(jsonEncode).join('\n') +
    '\n';

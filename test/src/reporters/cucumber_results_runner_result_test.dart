import 'dart:convert';

import 'package:bdd_framework/src/reporters/cucumber_results_reporter.dart';
import 'package:test/test.dart';

const _runId =
    '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
const _otherId =
    'abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789';
const _output = 'file:///c:/reports/results.ndjson';
const _otherOutput = 'file:///c:/reports/other.ndjson';
const _prefix = 'bdd_framework.messages.v1:';

Map<String, Object?> _event(
  String type, [
  Map<String, Object?> data = const {},
]) => {'type': type, 'time': 0, ...data};

Map<String, Object?> _start([Object? version = '0.1.1']) => _event('start', {
  'protocolVersion': version,
  'runnerVersion': '1.31.1',
  'pid': 42,
});

Map<String, Object?> _testStart([int id = 1]) => _event('testStart', {
  'test': {'id': id, 'name': 'test', 'suiteID': 0, 'groupIDs': <int>[]},
});

Map<String, Object?> _print(
  String message, {
  Object? id = 1,
  String kind = 'print',
}) => _event('print', {'testID': id, 'messageType': kind, 'message': message});

Map<String, Object?> _marker({
  String id = _runId,
  String output = _output,
  int testId = 1,
}) => _print('$_prefix${jsonEncode({'id': id, 'output': output})}', id: testId);

Map<String, Object?> _done([Object? success = true]) =>
    _event('done', {'success': success});

List<Map<String, Object?>> _valid() => [
  _start(),
  _testStart(),
  _marker(),
  _done(),
];

String _json(Iterable<Object?> events, {String newline = '\n'}) =>
    '${events.map(jsonEncode).join(newline)}$newline';

bool _read(
  String input, {
  int exitCode = 0,
  String id = _runId,
  String output = _output,
}) => readMessagesRunnerResult(
  input,
  runId: id,
  outputUri: output,
  testExitCode: exitCode,
);

void _reject(Iterable<Object?> events, {int exitCode = 0}) => expect(
  () => _read(_json(events), exitCode: exitCode),
  throwsFormatException,
);

void main() {
  test('accepts a completed passing run with its captured marker', () {
    expect(_read(_json(_valid())), isTrue);
  });

  test('a conclusive failure is returned only with exit code one', () {
    expect(
      _read(_json([..._valid().take(3), _done(false)]), exitCode: 1),
      isFalse,
    );
  });

  test('accepts CRLF and a complete final record without its newline', () {
    expect(_read(_json(_valid(), newline: '\r\n')), isTrue);
    expect(_read(_json(_valid()).trimRight()), isTrue);
  });

  test('supports protocol patches and additive event types', () {
    expect(
      _read(
        _json([
          _start('0.1.42'),
          _testStart(),
          _event('futureEvent', {'extra': 'metadata'}),
          _marker(),
          _done(),
        ]),
      ),
      isTrue,
    );
  });

  test('does not aggregate prior errors or failed attempts across retries', () {
    final events = [
      _start(), _testStart(),
      _event('error', {
        'testID': 1,
        'error': 'first attempt',
        'stackTrace': '',
        'isFailure': true,
      }),
      _event('testDone', {
        'testID': 1,
        'result': 'failure',
        'hidden': false,
        'skipped': false,
      }),
      _testStart(2),
      _event('testDone', {
        'testID': 2,
        'result': 'success',
        'hidden': false,
        'skipped': false,
      }),
      _testStart(3), // A hidden tearDownAll test can emit the reporter marker.
      _marker(testId: 3),
      _event('testDone', {
        'testID': 3,
        'result': 'success',
        'hidden': true,
        'skipped': false,
      }),
      _done(),
    ];
    expect(_read(_json(events)), isTrue);
  });

  test(
    'allows late errors from a known completed test and uses final done',
    () {
      final events = [
        _start(),
        _testStart(),
        _marker(),
        _event('testDone', {
          'testID': 1,
          'result': 'success',
          'hidden': false,
          'skipped': false,
        }),
        _event('error', {
          'testID': 1,
          'error': 'late',
          'stackTrace': '',
          'isFailure': false,
        }),
        _done(false),
      ];
      expect(_read(_json(events), exitCode: 1), isFalse);
    },
  );

  test('ignores valid markers for other output files', () {
    expect(
      _read(
        _json([
          _start(),
          _testStart(),
          _marker(id: _otherId, output: _otherOutput),
          _marker(),
          _marker(output: _otherOutput),
          _done(),
        ]),
      ),
      isTrue,
    );
  });

  test('ignores ordinary print content and a skip message is not a marker', () {
    final markerText = _marker()['message'] as String;
    expect(
      _read(
        _json([
          _start(),
          _testStart(),
          _print('note: $markerText'),
          _print(markerText, kind: 'skip'),
          _marker(),
          _done(),
        ]),
      ),
      isTrue,
    );
    _reject([
      _start(),
      _testStart(),
      _print(markerText, kind: 'skip'),
      _done(),
    ]);
  });

  test('requires exactly the expected identity for this output', () {
    _reject([_start(), _testStart(), _done()]);
    _reject([_start(), _testStart(), _marker(id: _otherId), _done()]);
    _reject([_start(), _testStart(), _marker(output: _otherOutput), _done()]);
  });

  test('rejects multiple markers for one path even with different nonces', () {
    _reject([_start(), _testStart(), _marker(), _marker(), _done()]);
    _reject([
      _start(),
      _testStart(),
      _marker(id: _otherId),
      _marker(),
      _done(),
    ]);
    _reject([
      _start(),
      _testStart(),
      _marker(),
      _testStart(2),
      _marker(id: _otherId, testId: 2),
      _done(),
    ]);
  });

  test('requires a marker print from a previously known test ID', () {
    _reject([_start(), _marker(), _testStart(), _done()]);
    for (final id in [null, -1, 1.0, '1', 2]) {
      _reject([
        _start(),
        _testStart(),
        {..._marker(), 'testID': id},
        _done(),
      ]);
    }
    _reject([
      _start(),
      _testStart(),
      {..._marker(), 'type': 'futureEvent'},
      _marker(),
      _done(),
    ]);
  });

  test('rejects duplicate or invalid testStart identities', () {
    _reject([_start(), _testStart(), _testStart(), _marker(), _done()]);
    for (final test in [
      null,
      <String, Object?>{},
      {'id': -1},
      {'id': '1'},
      {'id': 1.0},
    ]) {
      _reject([
        _start(),
        _event('testStart', {'test': test}),
        _marker(),
        _done(),
      ]);
    }
  });

  test('requires start first and one final done last', () {
    _reject(_valid().skip(1));
    _reject([_event('suite'), ..._valid()]);
    _reject([_start(), ..._valid()]);
    _reject(_valid().take(3));
    _reject([..._valid(), _done()]);
    _reject([..._valid(), _event('futureEvent')]);
    _reject([_start(), _testStart(), _done(), _marker()]);
  });

  test('rejects missing, null or nonboolean global success', () {
    for (final success in [null, 0, 1, 'true', 'false']) {
      _reject([..._valid().take(3), _done(success)]);
    }
    _reject([..._valid().take(3), _event('done')]);
  });

  test('rejects unsupported protocol versions', () {
    for (final version in [
      null,
      1,
      '',
      '0.0.1',
      '0.2.0',
      '1.0.0',
      '0.1',
      '0.1.1-beta',
      '0.1.01',
      '0.1.1\n',
    ]) {
      _reject([_start(version), ..._valid().skip(1)]);
    }
  });

  test('rejects unsupported exit codes and disagreement with done', () {
    for (final code in [-1, 2, 65, 130, 255]) {
      _reject(_valid(), exitCode: code);
    }
    _reject(_valid(), exitCode: 1);
    _reject([..._valid().take(3), _done(false)]);
  });

  test('every event must be an object with nonempty type and integer time', () {
    for (final event in [
      null,
      true,
      1,
      'text',
      <Object?>[],
      <String, Object?>{},
      {'type': 'futureEvent'},
      {'time': 0},
      {'type': '', 'time': 0},
      {'type': null, 'time': 0},
      {'type': 'futureEvent', 'time': -1},
      {'type': 'futureEvent', 'time': 0.5},
      {'type': 'futureEvent', 'time': '0'},
    ]) {
      _reject([_start(), _testStart(), event, _marker(), _done()]);
    }
  });

  test('rejects incoherent known print, error and testDone shapes', () {
    final events = [
      _event('print', {'testID': 1, 'messageType': 'print', 'message': 3}),
      _event('print', {'testID': 1, 'messageType': null, 'message': ''}),
      _event('error', {
        'testID': 2,
        'error': '',
        'stackTrace': '',
        'isFailure': false,
      }),
      _event('error', {
        'testID': 1,
        'error': '',
        'stackTrace': '',
        'isFailure': null,
      }),
      _event('testDone', {
        'testID': 1,
        'result': 'unknown',
        'hidden': false,
        'skipped': false,
      }),
      _event('testDone', {
        'testID': 1,
        'result': 'success',
        'hidden': null,
        'skipped': false,
      }),
    ];
    for (final event in events) {
      _reject([_start(), _testStart(), event, _marker(), _done()]);
    }
  });

  test('rejects malformed marker payloads without exposing their contents', () {
    for (final payload in [
      'secret-input',
      'null',
      '[]',
      '{}',
      jsonEncode({'id': 'bad', 'output': _output}),
      jsonEncode({'id': '$_runId\n', 'output': _output}),
      jsonEncode({'id': _runId, 'output': 1}),
      jsonEncode({'id': _runId, 'output': 'relative.ndjson'}),
      jsonEncode({'id': _runId, 'output': _output, 'extra': true}),
    ]) {
      expect(
        () => _read(
          _json([
            _start(),
            _testStart(),
            _print('$_prefix$payload'),
            _marker(),
            _done(),
          ]),
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.toString(),
            'sanitized error',
            isNot(contains('secret-input')),
          ),
        ),
      );
    }
  });

  test('rejects invalid expected identity or a noncanonical output URI', () {
    for (final id in ['', 'bad', '$_runId\n']) {
      expect(() => _read(_json(_valid()), id: id), throwsFormatException);
    }
    for (final output in [
      'report.ndjson',
      'https://example.com/report',
      'file:///a/../report.ndjson',
      'file:///report.ndjson?query',
      'file:///report.ndjson#fragment',
    ]) {
      expect(
        () => _read(_json(_valid()), output: output),
        throwsFormatException,
      );
    }
  });

  test(
    'rejects empty, mixed stdout, blank lines, invalid JSON or truncated done',
    () {
      for (final text in [
        '',
        'hello\n${_json(_valid())}',
        '\n${_json(_valid())}',
        '${_json(_valid())}\n',
        _json(_valid()).replaceFirst('\n', '\r'),
        '${_json(_valid().take(3))}{"type":"done","time":0,"success":',
        '${_json(_valid().take(3))}not-json\n',
      ]) {
        expect(() => _read(text), throwsFormatException);
      }
    },
  );

  test('enforces the event limit before decoding a million records', () {
    final chunk = List.filled(1000, '{}\n').join();
    final oversized = '${List.filled(1000, chunk).join()}{}\n';
    expect(
      () => _read(oversized),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('1000000'),
        ),
      ),
    );
  });

  test(
    'enforces the byte limit for multibyte UTF-8, not just String length',
    () {
      final chunk = List.filled(1024, 'é').join();
      final oversized = List.filled(32769, chunk).join();
      expect(oversized.length, lessThan(64 * 1024 * 1024));
      expect(
        () => _read(oversized),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('64 MiB'),
          ),
        ),
      );
    },
  );
}

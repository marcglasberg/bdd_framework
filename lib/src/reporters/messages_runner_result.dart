import 'dart:convert';

const _markerPrefix = 'bdd_framework.messages.v1:';
const _maximumBytes = 64 * 1024 * 1024;
const _maximumEvents = 1000000;
final _noncePattern = RegExp(r'^[0-9a-fA-F]{64}$');
final _protocolPattern = RegExp(r'^0\.1\.(?:0|[1-9][0-9]*)$');

/// Reads the dedicated JSON file reporter from one completed test-runner run.
///
/// [outputUri] is the canonical absolute file URI supplied by the caller (with
/// Windows case normalization already applied). This function performs no IO.
/// Only a coherent final `done.success` determines the result: earlier errors
/// may belong to failed attempts that were subsequently retried successfully.
/// Missing, malformed, ambiguous or inconsistent evidence throws rather than
/// guessing a result. Unknown event types with a valid base shape are allowed
/// for additive protocol compatibility.
bool readMessagesRunnerResult(
  String jsonLines, {
  required String runId,
  required String outputUri,
  required int testExitCode,
}) {
  if (!_validNonce(runId) || !_isOutputUri(outputUri)) {
    throw const FormatException('Invalid expected Messages run identity.');
  }
  if (testExitCode != 0 && testExitCode != 1) {
    throw const FormatException('Unsupported test-runner exit code.');
  }
  _checkBounds(jsonLines);

  final knownTests = <int>{};
  var started = false;
  bool? success;
  var outputMarkers = 0;
  var expectedMarker = false;

  for (final line in _lines(jsonLines)) {
    if (success != null) {
      throw const FormatException(
        'An event follows the final runner done event.',
      );
    }
    final event = _object(line, 'Invalid runner JSON event.');
    final type = event['type'];
    if (type is! String || type.isEmpty || !_nonnegativeInt(event['time'])) {
      throw const FormatException('Invalid runner event type or time.');
    }
    if (!started && type != 'start') {
      throw const FormatException('The first runner event must be start.');
    }

    switch (type) {
      case 'start':
        final version = event['protocolVersion'];
        if (started ||
            version is! String ||
            _protocolPattern.stringMatch(version) != version) {
          throw const FormatException(
            'Duplicate start or unsupported runner protocol.',
          );
        }
        started = true;
      case 'testStart':
        final test = event['test'];
        if (test is! Map<String, dynamic> || !_nonnegativeInt(test['id'])) {
          throw const FormatException('Invalid runner testStart identity.');
        }
        if (!knownTests.add(test['id'] as int)) {
          throw const FormatException('Duplicate runner test identity.');
        }
      case 'print':
        _knownTest(event['testID'], knownTests);
        final messageType = event['messageType'];
        final message = event['message'];
        if (messageType is! String ||
            messageType.isEmpty ||
            message is! String) {
          throw const FormatException('Invalid captured runner print event.');
        }
        if (messageType != 'print' || !message.startsWith(_markerPrefix)) {
          continue;
        }
        final marker = _object(
          message.substring(_markerPrefix.length),
          'Invalid Messages run marker.',
        );
        final markerId = marker['id'];
        final markerOutput = marker['output'];
        if (marker.length != 2 ||
            markerId is! String ||
            !_validNonce(markerId) ||
            markerOutput is! String ||
            !_isOutputUri(markerOutput)) {
          throw const FormatException('Invalid Messages run marker identity.');
        }
        if (markerOutput == outputUri) {
          outputMarkers++;
          if (outputMarkers > 1) {
            throw const FormatException(
              'Multiple Messages runs target the same output.',
            );
          }
          expectedMarker = markerId == runId;
        }
      case 'error':
        _knownTest(event['testID'], knownTests);
        if (event['error'] is! String ||
            event['stackTrace'] is! String ||
            event['isFailure'] is! bool) {
          throw const FormatException('Invalid runner error event.');
        }
      case 'testDone':
        _knownTest(event['testID'], knownTests);
        if (!const ['success', 'failure', 'error'].contains(event['result']) ||
            event['hidden'] is! bool ||
            event['skipped'] is! bool) {
          throw const FormatException('Invalid runner testDone event.');
        }
      case 'done':
        final completed = event['success'];
        if (completed is! bool) {
          throw const FormatException(
            'The test runner did not finish conclusively.',
          );
        }
        success = completed;
      default:
        // A marker is accepted only as a captured print from a known test.
        final message = event['message'];
        if (message is String && message.startsWith(_markerPrefix)) {
          throw const FormatException(
            'Messages marker is not a captured print event.',
          );
        }
    }
  }

  if (!started || success == null) {
    throw const FormatException('Incomplete test-runner JSON file.');
  }
  if (outputMarkers != 1 || !expectedMarker) {
    throw const FormatException('Missing expected Messages run marker.');
  }
  if (testExitCode != (success ? 0 : 1)) {
    throw const FormatException(
      'Runner done result disagrees with the exit code.',
    );
  }
  return success;
}

bool _nonnegativeInt(Object? value) => value is int && value >= 0;

bool _validNonce(String value) =>
    value.length == 64 && _noncePattern.hasMatch(value);

void _knownTest(Object? value, Set<int> knownTests) {
  if (!_nonnegativeInt(value) || !knownTests.contains(value)) {
    throw const FormatException('Runner event references an unknown test.');
  }
}

bool _isOutputUri(String value) {
  final uri = Uri.tryParse(value);
  return uri != null &&
      uri.scheme == 'file' &&
      uri.hasAbsolutePath &&
      !uri.hasQuery &&
      !uri.hasFragment &&
      uri.userInfo.isEmpty &&
      !uri.hasPort &&
      uri.normalizePath().path == uri.path;
}

Map<String, dynamic> _object(String line, String error) {
  try {
    final value = jsonDecode(line);
    if (value is Map<String, dynamic>) return value;
  } on FormatException {
    // Do not expose the JSON contents, which can contain test data or secrets.
  }
  throw FormatException(error);
}

/// Counts UTF-8 bytes without allocating a second, potentially larger copy.
/// Each NDJSON line is one event; check the event budget before decoding any.
void _checkBounds(String input) {
  if (input.isEmpty || input.length > _maximumBytes) {
    throw const FormatException('Runner JSON file is empty or exceeds 64 MiB.');
  }
  var bytes = 0;
  var lines = 0;
  for (var i = 0; i < input.length; i++) {
    final unit = input.codeUnitAt(i);
    if (unit == 10 && ++lines > _maximumEvents) {
      throw const FormatException('Runner JSON file exceeds 1000000 events.');
    }
    if (unit < 0x80) {
      bytes++;
    } else if (unit < 0x800) {
      bytes += 2;
    } else if (unit >= 0xd800 &&
        unit <= 0xdbff &&
        i + 1 < input.length &&
        input.codeUnitAt(i + 1) >= 0xdc00 &&
        input.codeUnitAt(i + 1) <= 0xdfff) {
      bytes += 4;
      i++;
    } else {
      bytes += 3;
    }
    if (bytes > _maximumBytes) {
      throw const FormatException('Runner JSON file exceeds 64 MiB.');
    }
  }
  if (!input.endsWith('\n') && ++lines > _maximumEvents) {
    throw const FormatException('Runner JSON file exceeds 1000000 events.');
  }
}

/// Accept LF or CRLF, including a complete final JSON record without a newline.
/// Blank lines and bare CR separators are not valid dedicated reporter output.
Iterable<String> _lines(String input) sync* {
  var start = 0;
  while (start < input.length) {
    final newline = input.indexOf('\n', start);
    var end = newline < 0 ? input.length : newline;
    if (newline >= 0 && end > start && input.codeUnitAt(end - 1) == 13) end--;
    final line = input.substring(start, end);
    if (line.trim().isEmpty || line.contains('\r')) {
      throw const FormatException('Invalid runner NDJSON line.');
    }
    yield line;
    start = newline < 0 ? input.length : newline + 1;
  }
}

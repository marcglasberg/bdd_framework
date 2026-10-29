import 'dart:io';

import 'package:bdd_framework/messages.dart';

const _usage =
    'Usage: dart run bdd_framework:finalize_messages '
    '--messages=<final.ndjson> --runner-json=<runner.json> --exit-code=<0|1>\n'
    'Run only after dart/flutter test exits. The .partial is consumed.\n'
    'Exit codes: 0 success, 1 confirmed test failure, 2 incomplete/export error.';

Future<void> main(List<String> args) async {
  if (args.length == 1 && args.single == '--help') {
    stdout.writeln(_usage);
    return;
  }
  try {
    final values = <String, String>{};
    for (final arg in args) {
      final separator = arg.indexOf('=');
      if (!arg.startsWith('--') || separator < 3) {
        throw const FormatException('Use --name=value arguments.');
      }
      final key = arg.substring(2, separator);
      final value = arg.substring(separator + 1);
      if (!{'messages', 'runner-json', 'exit-code'}.contains(key) ||
          value.isEmpty ||
          values.containsKey(key)) {
        throw const FormatException('Unknown, empty or repeated argument.');
      }
      values[key] = value;
    }
    if (values.length != 3) throw const FormatException('Missing arguments.');
    final result = await finalizeMessages(
      path: values['messages']!,
      runnerJsonPath: values['runner-json']!,
      testExitCode: int.parse(values['exit-code']!),
    );
    stdout.writeln('Cucumber Messages finalized: ${values['messages']}');
    exitCode = result ? 0 : 1;
  } catch (error) {
    stderr.writeln('Messages finalization failed: $error');
    stderr.writeln(_usage);
    exitCode = 2;
  }
}

import 'dart:io';

/// Runs [body] and returns everything it wrote to [stdout].
Future<String> captureStdout(Future<void> Function() body) async {
  final fake = _FakeStdout();
  await IOOverrides.runZoned(body, stdout: () => fake);
  return fake.buffer.toString();
}

class _FakeStdout implements Stdout {
  final buffer = StringBuffer();

  @override
  void write(Object? object) => buffer.write(object);

  @override
  void writeln([Object? object = '']) => buffer.writeln(object);

  @override
  void writeAll(Iterable objects, [String separator = '']) =>
      buffer.writeAll(objects, separator);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

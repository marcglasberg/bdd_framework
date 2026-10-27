import 'dart:convert';
import 'dart:io';

import 'package:bdd_framework/src/reporters/messages_file.dart';
import 'package:test/test.dart';

void main() {
  late Directory directory;
  late File destination;

  setUp(() async {
    final temporary = await Directory.systemTemp.createTemp(
      'bdd-safe-messages-',
    );
    // On macOS, the system temp path can itself contain a /var symlink.
    directory = Directory(await temporary.resolveSymbolicLinks());
    destination = File('${directory.path}/messages.ndjson');
  });
  tearDown(() async {
    await directory.delete(recursive: true);
  });

  test('creates parents and publishes complete UTF-8 lines', () async {
    final nested = File('${directory.path}/nested/reports/messages.ndjson');
    await writeMessagesFile(nested.path, () => ['{"value":"é"}', '{}']);
    expect(await nested.readAsString(), '{"value":"é"}\n{}\n');
    expect(await nested.parent.list().map((e) => e.uri).toList(), [nested.uri]);
  });

  test(
    'replaces a regular file only after invalidating the old artifact',
    () async {
      await destination.writeAsString('old success');
      await writeMessagesFile(destination.path, () {
        expect(destination.existsSync(), isFalse);
        return ['new report'];
      });
      expect(await destination.readAsString(), 'new report\n');
      expect(await directory.list().map((e) => e.uri).toList(), [
        destination.uri,
      ]);
    },
  );

  test('a builder error removes stale output and all staging files', () async {
    await destination.writeAsString('old success');
    final failure = StateError('cannot build');
    await expectLater(
      writeMessagesFile(destination.path, () => throw failure),
      throwsA(same(failure)),
    );
    expect(await directory.list().toList(), isEmpty);
  });

  test('an iterator error never publishes its partial output', () async {
    await destination.writeAsString('old success');
    Iterable<String> lines() sync* {
      yield 'first line';
      expect(destination.existsSync(), isFalse);
      throw StateError('later envelope failed');
    }

    await expectLater(
      writeMessagesFile(destination.path, lines),
      throwsStateError,
    );
    expect(await directory.list().toList(), isEmpty);
  });

  test('a file open error propagates and cleans staging files', () async {
    await destination.writeAsString('old success');
    final result = IOOverrides.runZoned(
      () => writeMessagesFile(destination.path, () => ['not published']),
      createFile: (path) {
        final realFile = File.fromRawPath(utf8.encode(path));
        return path.endsWith('/report.tmp')
            ? _CannotOpenFile(realFile)
            : realFile;
      },
    );
    await expectLater(result, throwsA(isA<FileSystemException>()));
    expect(await directory.list().toList(), isEmpty);
  });

  test(
    'a partial write error propagates without publishing the report',
    () async {
      await destination.writeAsString('old success');
      final result = IOOverrides.runZoned(
        () => writeMessagesFile(destination.path, () => ['not published']),
        createFile: (path) {
          final realFile = File.fromRawPath(utf8.encode(path));
          return path.endsWith('/report.tmp')
              ? _CannotWriteFile(realFile)
              : realFile;
        },
      );
      await expectLater(result, throwsA(isA<FileSystemException>()));
      expect(await directory.list().toList(), isEmpty);
    },
  );

  test(
    'rejects a directory destination before evaluating the builder',
    () async {
      await Directory(destination.path).create();
      var called = false;
      await expectLater(
        writeMessagesFile(destination.path, () {
          called = true;
          return [];
        }),
        throwsA(isA<FileSystemException>()),
      );
      expect(called, isFalse);
      expect(Directory(destination.path).existsSync(), isTrue);
    },
  );

  test('rejects a regular file used as a parent', () async {
    await destination.writeAsString('sentinel');
    await expectLater(
      writeMessagesFile('${destination.path}/child.ndjson', () => ['report']),
      throwsA(isA<FileSystemException>()),
    );
    expect(await destination.readAsString(), 'sentinel');
  });

  test(
    'does not confuse an existing special entry with an absent file',
    () async {
      // On Unix, dart:io reports some device types as notFound. Simulate that
      // result using our own sentinel, without touching a real device.
      await destination.writeAsString('sentinel');
      final result = IOOverrides.runWithIOOverrides(
        () => writeMessagesFile(destination.path, () => ['report']),
        _SpecialEntryType(destination.path),
      );
      await expectLater(result, throwsA(isA<FileSystemException>()));
      expect(await destination.readAsString(), 'sentinel');
    },
  );

  test('does not overwrite a destination created during the build', () async {
    await expectLater(
      writeMessagesFile(destination.path, () {
        destination.writeAsStringSync('another writer');
        return ['our report'];
      }),
      throwsA(isA<FileSystemException>()),
    );
    expect(await destination.readAsString(), 'another writer');
    expect(await directory.list().map((e) => e.uri).toList(), [
      destination.uri,
    ]);
  });

  test('limits encoded bytes, including line separators', () async {
    // Reuse one small string and bound the temporary file below 64 MiB.
    // Non-ASCII text ensures the limit counts bytes instead of code units.
    final chunk = 'é' * (512 * 1024);
    await expectLater(
      writeMessagesFile(
        destination.path,
        () => Iterable.generate(64, (_) => chunk),
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('$maxMessagesFileBytes byte output limit'),
        ),
      ),
    );
    expect(await directory.list().toList(), isEmpty);
  });

  test('rejects an output symlink without touching its target', () async {
    final sentinel = File('${directory.path}/sentinel.txt');
    await sentinel.writeAsString('keep');
    final link = Link(destination.path);
    if (!await _createLink(link, sentinel.path)) return;
    await expectLater(
      writeMessagesFile(destination.path, () => ['report']),
      throwsA(isA<FileSystemException>()),
    );
    expect(await sentinel.readAsString(), 'keep');
    expect(FileSystemEntity.isLinkSync(link.path), isTrue);
  });

  test('rejects a dangling output link', () async {
    final absent = File('${directory.path}/absent.txt');
    final link = Link(destination.path);
    if (!await _createLink(link, absent.path)) return;
    await expectLater(
      writeMessagesFile(destination.path, () => ['report']),
      throwsA(isA<FileSystemException>()),
    );
    expect(absent.existsSync(), isFalse);
    expect(FileSystemEntity.isLinkSync(link.path), isTrue);
  });

  test('rejects a directory link or junction ancestor', () async {
    final target = await Directory('${directory.path}/target').create();
    final sentinel = File('${target.path}/messages.ndjson');
    await sentinel.writeAsString('keep');
    final link = Link('${directory.path}/linked-parent');
    if (!await _createLink(link, target.path)) return;
    await expectLater(
      writeMessagesFile('${link.path}/messages.ndjson', () => ['report']),
      throwsA(isA<FileSystemException>()),
    );
    expect(await sentinel.readAsString(), 'keep');
    expect(await target.list().map((e) => e.uri).toList(), [sentinel.uri]);
  });

  test('does not normalize a linked ancestor away with dot-dot', () async {
    final target = await Directory('${directory.path}/target').create();
    final link = Link('${directory.path}/linked-parent');
    if (!await _createLink(link, target.path)) return;
    await destination.writeAsString('keep');
    await expectLater(
      writeMessagesFile('${link.path}/../messages.ndjson', () => ['report']),
      throwsA(isA<FileSystemException>()),
    );
    expect(await destination.readAsString(), 'keep');
  });

  test('rejects ambiguous and device paths on Windows', () async {
    if (!Platform.isWindows) return;
    for (final name in [
      'NUL',
      'CON.txt',
      'messages.ndjson:stream',
      'report.',
    ]) {
      await expectLater(
        writeMessagesFile('${directory.path}/$name', () => []),
        throwsA(isA<FileSystemException>()),
      );
    }
    expect(await directory.list().toList(), isEmpty);
  });
}

Future<bool> _createLink(Link link, String target) async {
  try {
    await link.create(target);
    return true;
  } on FileSystemException catch (error) {
    // Windows may require Developer Mode or a symlink privilege. This must be
    // visibly skipped rather than counted as a successful link-safety test.
    markTestSkipped('Links unavailable on this filesystem: ${error.osError}');
    return false;
  }
}

class _CannotOpenFile implements File {
  _CannotOpenFile(this.file);

  final File file;

  @override
  String get path => file.path;

  @override
  Future<File> create({bool recursive = false, bool exclusive = false}) async {
    await file.create(recursive: recursive, exclusive: exclusive);
    return this;
  }

  @override
  Future<RandomAccessFile> open({FileMode mode = FileMode.read}) async =>
      throw FileSystemException('Injected open failure', path);

  @override
  Future<FileSystemEntity> delete({bool recursive = false}) =>
      file.delete(recursive: recursive);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _SpecialEntryType extends IOOverrides {
  _SpecialEntryType(this.destination);

  final String destination;

  @override
  FileSystemEntityType fseGetTypeSync(String path, bool followLinks) =>
      path.replaceAll('\\', '/') == destination.replaceAll('\\', '/')
      ? FileSystemEntityType.notFound
      : super.fseGetTypeSync(path, followLinks);
}

class _CannotWriteFile extends _CannotOpenFile {
  _CannotWriteFile(super.file);

  @override
  Future<RandomAccessFile> open({FileMode mode = FileMode.read}) async =>
      _PartialWriteFailure(await file.open(mode: mode));
}

class _PartialWriteFailure implements RandomAccessFile {
  _PartialWriteFailure(this.file);

  final RandomAccessFile file;

  @override
  Future<RandomAccessFile> writeFrom(
    List<int> buffer, [
    int start = 0,
    int? end,
  ]) async {
    await file.writeFrom(buffer, start, start + 1);
    throw const FileSystemException('Injected failure after one byte');
  }

  @override
  Future<void> close() => file.close();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

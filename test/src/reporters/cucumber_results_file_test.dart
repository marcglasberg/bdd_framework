import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bdd_framework/src/reporters/cucumber_results_reporter.dart';
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
    destination = File('${directory.path}/results.ndjson');
  });
  tearDown(() async {
    await directory.delete(recursive: true);
  });

  group('reading and claiming', () {
    test(
      'reads strict UTF-8 across chunk boundaries without changing input',
      () async {
        final text = '${'a' * 65535}é\n';
        await destination.writeAsString(text);
        expect(await readMessagesFile(destination.path), text);
        expect(destination.existsSync(), isTrue);
      },
    );

    test(
      'consumes the source exactly once and removes staging files',
      () async {
        await destination.writeAsString('partial report');
        expect(await consumeMessagesFile(destination.path), 'partial report');
        expect(await directory.list().toList(), isEmpty);
        await expectLater(
          consumeMessagesFile(destination.path),
          throwsA(isA<FileSystemException>()),
        );
      },
    );

    test(
      'invalidates regular output and accepts an already absent path',
      () async {
        await destination.writeAsString('old report');
        await invalidateMessagesFile(destination.path);
        await invalidateMessagesFile(destination.path);
        expect(await directory.list().toList(), isEmpty);
      },
    );

    test(
      'a later JSON parse failure cannot reuse the consumed source',
      () async {
        await destination.writeAsString('{');
        await expectLater(() async {
          jsonDecode(await consumeMessagesFile(destination.path));
        }, throwsFormatException);
        expect(await directory.list().toList(), isEmpty);
      },
    );

    for (final consume in [false, true]) {
      final operation = consume ? consumeMessagesFile : readMessagesFile;
      final label = consume ? 'consume' : 'read';

      test('$label rejects oversized input before decoding', () async {
        final file = await destination.open(mode: FileMode.write);
        await file.truncate(maxMessagesFileBytes + 1);
        await file.close();
        await expectLater(operation(destination.path), throwsStateError);
        expect(destination.existsSync(), !consume);
        expect(await directory.list().length, consume ? 0 : 1);
      });

      test('$label rejects malformed UTF-8 and closes the file', () async {
        await destination.writeAsBytes([0x61, 0xc3]);
        await expectLater(operation(destination.path), throwsFormatException);
        expect(destination.existsSync(), !consume);
        expect(await directory.list().length, consume ? 0 : 1);
      });

      test('$label rejects a directory without removing it', () async {
        await Directory(destination.path).create();
        await expectLater(
          operation(destination.path),
          throwsA(isA<FileSystemException>()),
        );
        expect(Directory(destination.path).existsSync(), isTrue);
      });

      test(
        '$label rejects a link without reading or removing its target',
        () async {
          final target = File('${directory.path}/sentinel.txt');
          await target.writeAsString('sentinel');
          final link = Link(destination.path);
          if (!await _createLink(link, target.path)) return;
          await expectLater(
            operation(destination.path),
            throwsA(isA<FileSystemException>()),
          );
          expect(FileSystemEntity.isLinkSync(link.path), isTrue);
          expect(await target.readAsString(), 'sentinel');
        },
      );
    }

    test(
      'a read-open failure still consumes and cleans the claimed source',
      () async {
        await destination.writeAsString('partial report');
        final result = IOOverrides.runZoned(
          () => consumeMessagesFile(destination.path),
          createFile: (path) {
            final realFile = File.fromRawPath(utf8.encode(path));
            return path.endsWith('/report.tmp')
                ? _CannotReadFile(realFile)
                : realFile;
          },
        );
        await expectLater(result, throwsA(isA<FileSystemException>()));
        expect(await directory.list().toList(), isEmpty);
      },
    );

    test(
      'the byte limit still applies if input outgrows its initial length',
      () async {
        final file = await destination.open(mode: FileMode.write);
        await file.truncate(maxMessagesFileBytes + 1);
        await file.close();
        // Simulate a file that looked small when the read began. All reads still
        // use the real bounded chunks; no data is written outside this temp dir.
        final result = IOOverrides.runZoned(
          () => readMessagesFile(destination.path),
          createFile: (path) {
            final realFile = File.fromRawPath(utf8.encode(path));
            return path.replaceAll('\\', '/') ==
                    destination.path.replaceAll('\\', '/')
                ? _ShortReportedFile(realFile)
                : realFile;
          },
        );
        await expectLater(result, throwsStateError);
        expect(destination.existsSync(), isTrue);
      },
    );
  });

  test('creates parents and publishes complete UTF-8 lines', () async {
    final nested = File('${directory.path}/nested/reports/results.ndjson');
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
    final sentinel = File('${target.path}/results.ndjson');
    await sentinel.writeAsString('keep');
    final link = Link('${directory.path}/linked-parent');
    if (!await _createLink(link, target.path)) return;
    await expectLater(
      writeMessagesFile('${link.path}/results.ndjson', () => ['report']),
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
      writeMessagesFile('${link.path}/../results.ndjson', () => ['report']),
      throwsA(isA<FileSystemException>()),
    );
    expect(await destination.readAsString(), 'keep');
  });

  test('rejects ambiguous and device paths on Windows', () async {
    if (!Platform.isWindows) return;
    for (final name in [
      'NUL',
      'CON.txt',
      'results.ndjson:stream',
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

class _CannotReadFile extends _CannotOpenFile {
  _CannotReadFile(super.file);

  @override
  File get absolute => this;

  @override
  Directory get parent => file.parent;

  @override
  Uri get uri => file.uri;
}

class _ShortReportedFile extends _CannotReadFile {
  _ShortReportedFile(super.file);

  @override
  Future<RandomAccessFile> open({FileMode mode = FileMode.read}) async =>
      _ShortReportedLength(await file.open(mode: mode));
}

class _ShortReportedLength implements RandomAccessFile {
  _ShortReportedLength(this.file);

  final RandomAccessFile file;

  @override
  Future<int> length() async => 0;

  @override
  Future<Uint8List> read(int count) => file.read(count);

  @override
  Future<void> close() => file.close();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
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

import 'dart:convert';
import 'dart:io';

/// Maximum encoded report size, including the newline after every envelope.
/// This helper is internal to the reporters and is not exported by the package.
const maxMessagesFileBytes = 64 * 1024 * 1024;

/// Invalidates an earlier report after checking the destination and ancestors.
/// Links and special files are never removed through this operation.
Future<void> invalidateMessagesFile(String path) async {
  _validatePath(path);
  final file = File(path).absolute;
  await _checkParents(file.parent, create: true);
  final type = await _destinationType(file);
  if (type == FileSystemEntityType.file) await file.delete();
}

/// Reads strict UTF-8 from a regular file, bounded even if the file grows.
/// The file and its parent directories must remain trusted and unchanged while
/// being read; portable dart:io cannot make path checks and open atomic.
Future<String> readMessagesFile(String path) async {
  _validatePath(path);
  final file = File(path).absolute;
  await _requireRegularFile(file);
  final input = await file.open();
  String? result;
  Object? failure;
  StackTrace? failureStack;
  try {
    if (await input.length() > maxMessagesFileBytes) throw _sizeError();
    final text = StringBuffer();
    final decoder = const Utf8Decoder(
      allowMalformed: false,
    ).startChunkedConversion(StringConversionSink.fromStringSink(text));
    var bytesRead = 0;
    while (true) {
      final chunk = await input.read(64 * 1024);
      if (chunk.isEmpty) break;
      bytesRead += chunk.length;
      if (bytesRead > maxMessagesFileBytes) throw _sizeError();
      decoder.add(chunk);
    }
    decoder.close();
    result = text.toString();
  } catch (error, stackTrace) {
    failure = error;
    failureStack = stackTrace;
  }
  try {
    await input.close();
  } catch (error, stackTrace) {
    failure ??= error;
    failureStack ??= stackTrace;
  }
  if (failure != null) Error.throwWithStackTrace(failure, failureStack!);
  await _requireRegularFile(file);
  return result!;
}

/// Claims a partial report before reading it, so its path can be consumed once.
/// The claimed copy is removed even when reading or UTF-8 decoding fails. This
/// prevents reuse of the same file, not replay of a separately copied artifact.
/// As with writing, parent directories must be trusted during the operation.
Future<String> consumeMessagesFile(String path) async {
  _validatePath(path);
  final source = File(path).absolute;
  await _requireRegularFile(source);
  Directory? claimDirectory;
  File? claimedFile;
  String? result;
  Object? failure;
  StackTrace? failureStack;
  try {
    claimDirectory = await source.parent.createTemp('.bdd-messages-claimed-');
    claimedFile = File('${claimDirectory.path}/report.tmp');
    await source.rename(claimedFile.path);
    result = await readMessagesFile(claimedFile.path);
  } catch (error, stackTrace) {
    failure = error;
    failureStack = stackTrace;
  }
  try {
    if (claimDirectory != null && claimedFile != null) {
      await _removeTemporary(claimDirectory, claimedFile);
    }
  } catch (error, stackTrace) {
    failure ??= error;
    failureStack ??= stackTrace;
  }
  if (failure != null) Error.throwWithStackTrace(failure, failureStack!);
  return result!;
}

Future<void> _requireRegularFile(File file) async {
  await _checkParents(file.parent, create: false);
  if (await _destinationType(file) != FileSystemEntityType.file) {
    throw FileSystemException(
      'Expected an existing regular report file',
      file.path,
    );
  }
}

/// Publishes a complete UTF-8 report, or leaves no partially written report.
///
/// Existing regular output is invalidated before [lines] is called, so a failed
/// build cannot leave an old successful report behind. The replacement is
/// flushed and closed in the same filesystem before being renamed into place.
///
/// Output and ancestor links (including Windows junctions) are rejected. The
/// parent directories must nevertheless be trusted and must not be changed by
/// other processes during this operation: portable dart:io does not provide
/// directory handles and no-follow operations that would eliminate these races.
/// A cleanup error after the rename can leave a complete, published report.
Future<void> writeMessagesFile(
  String path,
  Iterable<String> Function() lines,
) async {
  _validatePath(path);
  final destination = File(path).absolute;
  await invalidateMessagesFile(destination.path);

  Directory? temporaryDirectory;
  File? temporaryFile;
  RandomAccessFile? output;
  Object? failure;
  StackTrace? failureStack;
  try {
    // createTemp reserves a unique directory; an existing link cannot be used
    // as the staging location. The directory is on the destination filesystem.
    temporaryDirectory = await destination.parent.createTemp('.bdd-messages-');
    temporaryFile = File('${temporaryDirectory.path}/report.tmp');
    await temporaryFile.create(exclusive: true);
    output = await temporaryFile.open(mode: FileMode.write);

    var bytesWritten = 0;
    for (final line in lines()) {
      final remaining = maxMessagesFileBytes - bytesWritten - 1;
      // UTF-8 needs at least as many bytes as UTF-16 code units. Check before
      // allocating the encoded line, then check its actual byte size as well.
      if (line.length > remaining) throw _sizeError();
      final bytes = utf8.encode(line);
      if (bytes.length > remaining) throw _sizeError();
      await output.writeFrom(bytes);
      await output.writeByte(10);
      bytesWritten += bytes.length + 1;
    }
    await output.flush();
    await output.close();
    output = null;

    await _checkParents(destination.parent, create: false);
    await _checkParents(temporaryDirectory, create: false);
    if (await _destinationType(temporaryFile) != FileSystemEntityType.file) {
      throw FileSystemException(
        'Temporary report file changed',
        temporaryFile.path,
      );
    }
    if (await _destinationType(destination) != FileSystemEntityType.notFound) {
      throw FileSystemException(
        'The report destination changed while the report was built',
        destination.path,
      );
    }
    await temporaryFile.rename(destination.path);
  } catch (error, stackTrace) {
    failure = error;
    failureStack = stackTrace;
  }

  try {
    await output?.close();
  } catch (error, stackTrace) {
    failure ??= error;
    failureStack ??= stackTrace;
  }
  try {
    if (temporaryDirectory != null && temporaryFile != null) {
      await _removeTemporary(temporaryDirectory, temporaryFile);
    }
  } catch (error, stackTrace) {
    failure ??= error;
    failureStack ??= stackTrace;
  }
  if (failure != null) Error.throwWithStackTrace(failure, failureStack!);
}

StateError _sizeError() => StateError(
  'Cucumber Messages exceed the $maxMessagesFileBytes byte output limit',
);

void _validatePath(String path) {
  final parts = path.split(Platform.isWindows ? RegExp(r'[/\\]') : '/');
  if (path.isEmpty ||
      parts.last.isEmpty ||
      parts.last == '.' ||
      parts.last == '..' ||
      path.contains('\x00')) {
    throw FileSystemException('Expected a regular report file path', path);
  }
  if (!Platform.isWindows) return;
  final windowsPath = path.replaceAll('/', '\\');
  if (windowsPath.startsWith(r'\\?\') ||
      windowsPath.startsWith(r'\\.\') ||
      RegExp(r'^[a-zA-Z]:[^/\\]').hasMatch(path)) {
    throw FileSystemException('Unsupported Windows report path', path);
  }
  final reserved = RegExp(
    r'^(con|prn|aux|nul|conin\$|conout\$|clock\$|com[1-9\u00b9\u00b2\u00b3]|lpt[1-9\u00b9\u00b2\u00b3])(?:\.|$)',
    caseSensitive: false,
  );
  for (final part in parts) {
    if (part.isEmpty ||
        part == '.' ||
        part == '..' ||
        RegExp(r'^[a-zA-Z]:$').hasMatch(part))
      continue;
    if (part.contains(':') ||
        part.endsWith('.') ||
        part.endsWith(' ') ||
        reserved.hasMatch(part)) {
      throw FileSystemException(
        'Ambiguous or special Windows report path',
        path,
      );
    }
  }
}

Future<void> _checkParents(Directory parent, {required bool create}) async {
  final ancestors = <Directory>[];
  var directory = parent;
  while (true) {
    ancestors.add(directory);
    // A UNC share is the filesystem root; its server name alone is not a
    // directory that dart:io can validate.
    if (Platform.isWindows) {
      final windowsPath = directory.path.replaceAll('/', '\\');
      if (windowsPath.startsWith(r'\\') &&
          windowsPath.split('\\').where((part) => part.isNotEmpty).length ==
              2) {
        break;
      }
    }
    final next = directory.parent;
    if (next.path == directory.path) break;
    directory = next;
  }
  // Do not normalize away '..': the preceding component can itself be a link.
  for (final ancestor in ancestors.reversed) {
    var type = FileSystemEntity.typeSync(ancestor.path, followLinks: false);
    if (type == FileSystemEntityType.notFound && create) {
      await ancestor.create();
      type = FileSystemEntity.typeSync(ancestor.path, followLinks: false);
    }
    if (type != FileSystemEntityType.directory) {
      throw FileSystemException(
        'Report parent must be a directory, not a link or special file',
        ancestor.path,
      );
    }
  }
}

Future<FileSystemEntityType> _destinationType(File file) async {
  final type = FileSystemEntity.typeSync(file.path, followLinks: false);
  if (type == FileSystemEntityType.file) return type;
  if (type == FileSystemEntityType.notFound) {
    // Some platforms report devices as notFound. Enumerating the checked
    // parent distinguishes a missing name from an existing special file;
    // errors listing the parent propagate instead of being treated as absence.
    final name = file.uri.pathSegments.last;
    await for (final entity in file.parent.list(followLinks: false)) {
      final entryName = entity.uri.pathSegments.where((s) => s.isNotEmpty).last;
      if (Platform.isWindows
          ? entryName.toLowerCase() == name.toLowerCase()
          : entryName == name) {
        throw FileSystemException(
          'Report destination is not a regular file',
          file.path,
        );
      }
    }
    return type;
  }
  throw FileSystemException(
    'Report destination must be a regular file, not a link or directory',
    file.path,
  );
}

Future<void> _removeTemporary(Directory directory, File file) async {
  await _checkParents(directory.parent, create: false);
  final directoryType = FileSystemEntity.typeSync(
    directory.path,
    followLinks: false,
  );
  if (directoryType == FileSystemEntityType.notFound) return;
  if (directoryType == FileSystemEntityType.link) {
    await Link(directory.path).delete();
    return;
  }
  if (directoryType != FileSystemEntityType.directory) {
    throw FileSystemException(
      'Temporary report directory changed',
      directory.path,
    );
  }
  final type = FileSystemEntity.typeSync(file.path, followLinks: false);
  if (type == FileSystemEntityType.file) {
    await file.delete();
  } else if (type == FileSystemEntityType.link) {
    await Link(file.path).delete();
  } else if (type != FileSystemEntityType.notFound) {
    throw FileSystemException('Temporary report file changed', file.path);
  }
  // Never recursively delete an unexpected entry or follow a substituted link.
  await directory.delete();
}

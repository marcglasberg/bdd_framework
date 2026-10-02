import 'dart:io';

import '../core.dart';

class FeatureFileReporter extends BddReporter {
  //
  /// Change this to output the results to another dir.
  static String dir = './gen_features/';

  final bool clearAllOutputBeforeRun;

  FeatureFileReporter({this.clearAllOutputBeforeRun = false});

  @override
  Future<void> report() async {
    await _init();
    await _generate();
    await _finish();
  }

  /// Add a bar to the end of dir, only if necessary.
  /// An empty dir means the current directory (and not the filesystem root).
  String get directory => dir.isEmpty
      ? "./"
      : (dir.endsWith("/") || dir.endsWith("\\"))
          ? dir
          : dir + "/";

  Future<void> _init() async {
    //
    if (clearAllOutputBeforeRun) await _deleteFeatureFiles();

    stdout.writeln("Feature files will be saved in $directory");
  }

  /// Deletes only the `.feature` files directly inside the [directory].
  /// Other files, subdirectories and links are never deleted.
  Future<void> _deleteFeatureFiles() async {
    stdout.writeln("Deleting all generated feature files from $directory");

    final folder = Directory(directory);
    try {
      if (!folder.existsSync()) return;

      await for (final entity in folder.list(followLinks: false)) {
        if (entity is File && entity.path.endsWith('.feature')) {
          try {
            await entity.delete();
          } catch (e) {
            stdout.writeln("Could not delete ${entity.path}: $e");
          }
        }
      }
    } catch (e) {
      stdout.writeln("Could not delete previously generated feature files: $e");
    }
  }

  Future<void> _generate() async {
    for (BddFeature feature in features) {
      IOSink? sink;

      try {
        final fileName = normalizeFileName(feature.title);
        final file =
            await File('$directory$fileName.feature').create(recursive: true);

        stdout.write("Generating $file. ");
        sink = file.openWrite();
        sink.write(feature);

        if (feature.backgroundFramework != null) {
          sink.write('\n');
          sink.write(feature.background.toString());
        }

        for (var i = 0; i < feature.testResults.length; i++) {
          _writeScenario(sink, feature.testResults[i]);
        }

        stdout.writeln("Done!");
      }
      //
      catch (e) {
        stdout.writeln("Failed!");
      }
      //
      finally {
        await sink?.flush();
        await sink?.close();
      }
    }
  }

  Future<void> _finish() async => stdout.writeln("Finished.");

  void _writeScenario(IOSink sink, TestResult test) async {
    sink.write('\n');
    test.terms.forEach((term) {
      sink.write(term.toString());
      sink.write('\n');
    });
  }
}

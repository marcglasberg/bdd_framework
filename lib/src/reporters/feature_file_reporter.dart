import 'dart:io';

import '../bdd_base.dart';

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
  String get directory => (dir.endsWith("/") || dir.endsWith("\\")) ? dir : dir + "/";

  Future<void> _init() async {
    //
    if (clearAllOutputBeforeRun) {
      stdout.writeln("Deleting all generated feature files from $directory");
      try {
        await File(directory).delete(recursive: true);
      } catch (e) {
        stdout.writeln("Could not delete previously generated feature files.");
      }
    }

    stdout.writeln("Feature files will be saved in $directory");
  }

  Future<void> _generate() async {
    for (BddFeature feature in features) {
      IOSink? sink;

      try {
        final fileName = normalizeFileName(feature.title);
        final file = await File('$directory$fileName.feature').create(recursive: true);

        stdout.write("Generating $file. ");
        sink = file.openWrite();
        sink.write(feature);
        sink.write('\n');

        feature.testResults.forEach((testResult) => _writeScenario(sink, testResult));

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

  void _writeScenario(IOSink? sink, TestResult test) async {
    sink?.write('\n');
    test.terms.forEach((term) {
      sink?.write(term.toString());
      sink?.write('\n');
    });
  }
}

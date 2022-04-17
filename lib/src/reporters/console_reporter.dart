import 'dart:io';

import '../bdd_base.dart';

class ConsoleReporter extends BddReporter {
  static const config = BddConfig(rightAlignKeywords: true);

  @override
  Future<void> report() async {
    int count = 0;

    for (BddFeature feature in features) {
      count++;
      stdout.writeln("$BddFeature $count --------------\n");
      if (feature.isNotEmpty) {
        var featureStr = feature.toString(config);
        stdout.writeln(featureStr);
      }

      for (TestResult testResult in feature.testResults) {
        stdout.writeln(testResult.toString(config) + "\n");
      }
    }
  }
}

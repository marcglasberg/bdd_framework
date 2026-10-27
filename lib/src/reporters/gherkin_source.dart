import '../core.dart';

/// The Gherkin text of [feature], with its background and all its BDDs.
///
/// This is the content of the `.feature` file the [FeatureFileReporter]
/// writes, and the source the `MessagesReporter` reports.
String gherkinSource(BddFeature feature) {
  final result = StringBuffer()..write(feature);

  if (feature.backgroundFramework != null) {
    result
      ..write('\n')
      ..write(feature.background.toString());
  }

  for (final test in feature.testResults) {
    result.write('\n');
    for (final term in test.terms) {
      result
        ..write(term.toString())
        ..write('\n');
    }
  }

  return result.toString();
}

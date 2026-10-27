import '../core.dart';

/// The Gherkin text of [feature], with its background and all its BDDs.
///
/// This is the content of the `.feature` file the [FeatureFileReporter]
/// writes, and the source the `MessagesReporter` reports.
String gherkinSource(BddFeature feature, {int? maxLength}) {
  final result = StringBuffer();
  void append(Object value) {
    final text = value.toString();
    if (maxLength != null && result.length + text.length > maxLength) {
      throw StateError(
        'Gherkin source exceeded the $maxLength character limit.',
      );
    }
    result.write(text);
  }

  append(feature);

  if (feature.backgroundFramework != null) {
    append('\n');
    append(feature.background.toString());
  }

  for (final test in feature.testResults) {
    append('\n');
    for (final term in test.terms) {
      append(term.toString());
      append('\n');
    }
  }

  return result.toString();
}

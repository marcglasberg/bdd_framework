import 'dart:io';

import 'package:bdd_framework/dart_test.dart';
import 'package:cucumber_gherkin/cucumber_gherkin.dart';
import 'package:cucumber_messages/cucumber_messages.dart';

/// Test helpers that run the exported `.feature` text through the official
/// Gherkin parser (`cucumber_gherkin`) and flatten the resulting Cucumber
/// Messages tree into plain Dart values.
///
/// The flattening matters: asserting on plain records and `List<List<String>>`
/// keeps the tests readable, and it lets them check the *structure* the parser
/// produced rather than only whether parsing threw.
///
/// Tests should assert against these plain types, not against the message
/// tree, so a `cucumber_messages` upgrade cannot churn every expectation.

/// Writes [feature] to a temporary directory with [FeatureFileReporter] and
/// returns the generated `.feature` text.
///
/// [bdds] must already be built against [feature]. Reporters are registered
/// after the BDDs are built because [BddRunner] only hands them to the
/// reporters at run time (see `lib/src/core/bdd_runner.dart`).
///
/// The global [FeatureFileReporter.dir] and the static reporter list are both
/// restored before returning, so these helpers cannot leak into other tests.
Future<String> exportFeature(
  BddFeature feature,
  List<BddFramework> bdds,
) async {
  final directory = await Directory.systemTemp.createTemp('bdd-gherkin-');
  final previousDir = FeatureFileReporter.dir;

  try {
    FeatureFileReporter.dir = directory.path;
    final reporter = FeatureFileReporter();
    BddReporter.set(reporter);

    // `BddRunner.run()` is what registers each BDD with the active reporters.
    // The [TestInvocation]s it hands to the delegate are discarded: their
    // bodies only run step code and print to the console, and
    // `FeatureFileReporter._generate()` writes `terms` without ever reading
    // `passed`. Running them would not change a byte of the exported file.
    for (final bdd in bdds) {
      BddRunner().run(bdd, (_) {}, (_) {}, null);
    }

    await reporter.report();

    // `FeatureFileReporter._generate()` catches every write error and only
    // prints "Failed!", so a missing file would otherwise look like a pass.
    final files = directory
        .listSync()
        .whereType<File>()
        .where((file) => file.path.endsWith('.feature'))
        .toList();

    if (files.length != 1) {
      throw StateError(
        'Expected exactly one .feature file in ${directory.path}, '
        'found ${files.map((file) => file.path).toList()}.',
      );
    }

    return files.single.readAsStringSync();
  } finally {
    BddReporter.set();
    FeatureFileReporter.dir = previousDir;
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  }
}

/// Parses [source] with `cucumber_gherkin` and flattens the result.
///
/// Parse failures surface as [ParsedFeature.errors] rather than exceptions,
/// which is how `generateMessages` reports them.
ParsedFeature parseFeature(String source, {String uri = 'bdd.feature'}) {
  final envelopes = generateMessages(source, uri);

  final errors = <String>[
    for (final envelope in envelopes)
      if (envelope.parseError != null) envelope.parseError!.message,
  ];

  final pickles = <ParsedPickle>[
    for (final envelope in envelopes)
      if (envelope.pickle != null)
        ParsedPickle(
          name: envelope.pickle!.name,
          steps: <ParsedPickleStep>[
            for (final step in envelope.pickle!.steps)
              ParsedPickleStep(
                text: step.text,
                table: step.argument?.dataTable == null
                    ? null
                    : <List<String>>[
                        for (final row in step.argument!.dataTable!.rows)
                          <String>[
                            for (final cell in row.cells) cell.value,
                          ],
                      ],
              ),
          ],
        ),
  ];

  final document = envelopes
      .where((envelope) => envelope.gherkinDocument != null)
      .map((envelope) => envelope.gherkinDocument!)
      .firstOrNull;
  final feature = document?.feature;

  if (feature == null) {
    return ParsedFeature(
      errors: errors,
      keyword: '',
      name: '',
      description: '',
      language: '',
      background: null,
      scenarios: const [],
      pickles: pickles,
      comments: document == null
          ? const []
          : <String>[for (final comment in document.comments) comment.text],
    );
  }

  ParsedScenario? background;
  final scenarios = <ParsedScenario>[];

  for (final child in feature.children) {
    final childBackground = child.background;
    if (childBackground != null) {
      background = ParsedScenario(
        keyword: childBackground.keyword.trim(),
        name: childBackground.name,
        description: childBackground.description,
        steps: _steps(childBackground.steps),
        examples: const [],
      );
      continue;
    }

    final scenario = child.scenario;
    if (scenario != null) {
      scenarios.add(
        ParsedScenario(
          keyword: scenario.keyword.trim(),
          name: scenario.name,
          description: scenario.description,
          steps: _steps(scenario.steps),
          examples: <ParsedExamples>[
            for (final examples in scenario.examples)
              ParsedExamples(
                keyword: examples.keyword.trim(),
                name: examples.name,
                table: <List<String>>[
                  if (examples.tableHeader != null)
                    <String>[
                      for (final cell in examples.tableHeader!.cells)
                        cell.value,
                    ],
                  for (final row in examples.tableBody)
                    <String>[for (final cell in row.cells) cell.value],
                ],
              ),
          ],
        ),
      );
    }
  }

  return ParsedFeature(
    errors: errors,
    keyword: feature.keyword.trim(),
    name: feature.name,
    description: feature.description,
    language: feature.language,
    background: background,
    scenarios: scenarios,
    pickles: pickles,
    comments: <String>[for (final comment in document!.comments) comment.text],
  );
}

List<ParsedStep> _steps(List<Step> steps) => <ParsedStep>[
      for (final step in steps)
        ParsedStep(
          keyword: step.keyword.trim(),
          text: step.text,
          table: step.dataTable == null
              ? null
              : <List<String>>[
                  for (final row in step.dataTable!.rows)
                    <String>[for (final cell in row.cells) cell.value],
                ],
        ),
    ];

/// A `.feature` file as the official parser understood it.
final class ParsedFeature {
  const ParsedFeature({
    required this.errors,
    required this.keyword,
    required this.name,
    required this.description,
    required this.language,
    required this.background,
    required this.scenarios,
    required this.pickles,
    required this.comments,
  });

  /// Parse error messages, verbatim. Empty when the source is valid Gherkin.
  final List<String> errors;
  final String keyword;
  final String name;

  /// The free-form feature description, as written by `BddFeature.userStory`.
  final String description;
  final String language;
  final ParsedScenario? background;
  final List<ParsedScenario> scenarios;

  /// One pickle per executable example. A `Scenario Outline` with two
  /// `Examples` rows produces two pickles, with `<placeholders>` substituted.
  final List<ParsedPickle> pickles;

  /// Every `#` comment line, each with its original indentation, in source
  /// order. This is where `note()` output lands.
  final List<String> comments;

  bool get isValid => errors.isEmpty;
}

final class ParsedScenario {
  const ParsedScenario({
    required this.keyword,
    required this.name,
    required this.description,
    required this.steps,
    required this.examples,
  });

  /// `Scenario`, `Scenario Outline`, or `Background`.
  final String keyword;
  final String name;
  final String description;
  final List<ParsedStep> steps;
  final List<ParsedExamples> examples;

  List<String> get stepLines => <String>[
        for (final step in steps) '${step.keyword} ${step.text}',
      ];
}

final class ParsedStep {
  const ParsedStep({
    required this.keyword,
    required this.text,
    required this.table,
  });

  /// `Given`, `When`, `Then`, `And`, or `But`.
  final String keyword;
  final String text;

  /// Header row first, or null when the step carries no data table.
  final List<List<String>>? table;
}

final class ParsedExamples {
  const ParsedExamples({
    required this.keyword,
    required this.name,
    required this.table,
  });

  final String keyword;
  final String name;

  /// Header row first.
  final List<List<String>> table;
}

final class ParsedPickle {
  const ParsedPickle({required this.name, required this.steps});

  final String name;
  final List<ParsedPickleStep> steps;

  List<String> get stepTexts => <String>[
        for (final step in steps) step.text,
      ];
}

final class ParsedPickleStep {
  const ParsedPickleStep({required this.text, required this.table});

  final String text;
  final List<List<String>>? table;
}

import 'dart:io';

import 'package:bdd_framework/dart_test.dart';
import 'package:cucumber_gherkin/cucumber_gherkin.dart';
import 'package:cucumber_messages/cucumber_messages.dart';

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

    // The delegate is a no-op: the reporter exports terms, never results.
    for (final bdd in bdds) {
      BddRunner().run(bdd, (_) {}, (_) {}, null);
    }

    await reporter.report();

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

ParsedFeature parseFeature(String source) {
  final envelopes = generateMessages(source, 'bdd.feature');

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

  final List<String> errors;
  final String keyword;
  final String name;
  final String description;
  final String language;
  final ParsedScenario? background;
  final List<ParsedScenario> scenarios;
  final List<ParsedPickle> pickles;
  final List<String> comments;
}

final class ParsedScenario {
  const ParsedScenario({
    required this.keyword,
    required this.name,
    required this.description,
    required this.steps,
    required this.examples,
  });

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

  final String keyword;
  final String text;
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

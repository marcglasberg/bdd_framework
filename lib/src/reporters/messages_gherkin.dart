// Pickle compilation follows cucumber_gherkin 42.0.1, with bounded,
// single-pass interpolation instead of recursively replacing example values.
// https://github.com/cucumber/gherkin/tree/main/dart
//
// MIT License
// Copyright (c) 2017 Cucumber Ltd, Gaspar Nagy, Björn Rasmusson,
// Peter Sergeant, and contributors
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import 'package:cucumber_gherkin/cucumber_gherkin.dart' as gherkin;
import 'package:cucumber_messages/cucumber_messages.dart' as messages;

const _maxSourceCharacters = 1024 * 1024;
const _maxExpandedCharacters = 16 * 1024 * 1024;
const _maxGeneratedItems = 100000;
const _maxExampleColumns = 256;

/// Parses Gherkin without the upstream recursive example substitution.
///
/// Each source has at most 1 Mi UTF-16 code units. The shared [budget] permits
/// 16 Mi code units of source plus emitted text and 100,000 generated cases,
/// steps, table rows/cells and tags combined. Omitting it creates a fresh budget.
/// Examples have at most 256 columns, bounding the matcher before
/// it is constructed. A limit or ambiguous table throws [FormatException]
/// before the next output allocation. Parser errors remain parse-error envelopes
/// for the reporter to reject along with other invalid Gherkin.
List<messages.Envelope> safeGherkinMessages(
  String source,
  String uri,
  String Function() idGenerator, {
  GherkinMessageBudget? budget,
}) {
  if (source.length > _maxSourceCharacters) {
    throw const FormatException(
      'Gherkin source exceeds the 1 Mi character limit.',
    );
  }
  final sharedBudget = budget ?? GherkinMessageBudget();
  // Source and AST retain descriptions/comments that do not occur in pickles.
  // Account for them cumulatively before parsing another feature.
  sharedBudget._consumeCharacters(source.length);
  final envelopes = gherkin.generateMessages(
    source,
    uri,
    gherkin.GherkinOptions(includePickles: false, idGenerator: idGenerator),
  );
  if (envelopes.any((envelope) => envelope.parseError != null))
    return envelopes;

  final documents = envelopes
      .map((envelope) => envelope.gherkinDocument)
      .whereType<messages.GherkinDocument>();
  final compiler = _PickleCompiler(uri, idGenerator, sharedBudget);
  for (final document in documents.toList()) {
    compiler.compile(document, envelopes);
  }
  return envelopes;
}

/// Internal report-wide budget shared by all feature compilations.
///
/// A failed compilation consumes its reservations; discard the report and use a
/// new budget for a new report instead of retrying with a partially used budget.
class GherkinMessageBudget {
  int _characters = 0;
  int _items = 0;

  void _consumeCharacters(int count) {
    if (count > _maxExpandedCharacters - _characters) {
      throw const FormatException(
        'Gherkin source and expanded text exceed the 16 Mi character limit.',
      );
    }
    _characters += count;
  }

  String _literal(String value) {
    _consumeCharacters(value.length);
    return value;
  }

  void _item() {
    if (_items >= _maxGeneratedItems) {
      throw const FormatException(
        'Gherkin exceeds the 100000 generated item limit.',
      );
    }
    _items++;
  }
}

/// Matches only complete, literal header tokens in the original string.
/// Longest tokens win at the same position; replacements are never rescanned.
class _ExampleTokens {
  _ExampleTokens(List<messages.TableCell> headers) : width = headers.length {
    if (width > _maxExampleColumns) {
      throw const FormatException('Examples exceeds the 256 column limit.');
    }
    for (var i = 0; i < headers.length; i++) {
      final token = '<${headers[i].value}>';
      if (_columnOf.containsKey(token)) {
        throw const FormatException(
          'Duplicate Examples column names are ambiguous.',
        );
      }
      _columnOf[token] = i;
    }
    final tokens = _columnOf.keys.toList()
      ..sort((a, b) {
        final byLength = b.length.compareTo(a.length);
        return byLength == 0 ? a.compareTo(b) : byLength;
      });
    _pattern = tokens.isEmpty
        ? null
        : RegExp(tokens.map(RegExp.escape).join('|'));
  }

  final int width;
  final Map<String, int> _columnOf = {};
  late final RegExp? _pattern;

  void validate(messages.TableRow row) {
    if (row.cells.length != width) {
      throw const FormatException(
        'Examples row width does not match its header.',
      );
    }
  }

  String render(
    String original,
    messages.TableRow row,
    GherkinMessageBudget budget,
  ) {
    final pattern = _pattern;
    if (pattern == null) return budget._literal(original);
    final buffer = StringBuffer();
    var position = 0;
    for (final match in pattern.allMatches(original)) {
      budget._consumeCharacters(match.start - position);
      buffer.write(original.substring(position, match.start));
      final replacement = row.cells[_columnOf[match.group(0)]!].value;
      budget._consumeCharacters(replacement.length);
      buffer.write(replacement);
      position = match.end;
    }
    budget._consumeCharacters(original.length - position);
    buffer.write(original.substring(position));
    return buffer.toString();
  }
}

class _PickleCompiler {
  _PickleCompiler(this.uri, this.idGenerator, this._budget);

  final String uri;
  final String Function() idGenerator;
  final GherkinMessageBudget _budget;

  void compile(
    messages.GherkinDocument document,
    List<messages.Envelope> output,
  ) {
    final feature = document.feature;
    if (feature == null) return;
    List<messages.Step> background = const [];
    for (final child in feature.children) {
      if (child.background != null) {
        background = child.background!.steps;
      } else if (child.scenario != null) {
        _scenario(
          child.scenario!,
          background,
          feature.tags,
          feature.language,
          output,
        );
      } else if (child.rule != null) {
        final rule = child.rule!;
        Iterable<messages.Step> ruleBackground = background;
        for (final ruleChild in rule.children) {
          if (ruleChild.background != null) {
            ruleBackground = background.followedBy(ruleChild.background!.steps);
          } else if (ruleChild.scenario != null) {
            _scenario(
              ruleChild.scenario!,
              ruleBackground,
              feature.tags.followedBy(rule.tags),
              feature.language,
              output,
            );
          } else {
            throw const FormatException('Unsupported Gherkin rule child.');
          }
        }
      } else {
        throw const FormatException('Unsupported Gherkin feature child.');
      }
    }
  }

  void _scenario(
    messages.Scenario scenario,
    Iterable<messages.Step> background,
    Iterable<messages.Tag> inheritedTags,
    String language,
    List<messages.Envelope> output,
  ) {
    final tags = inheritedTags.followedBy(scenario.tags);
    if (scenario.examples.isEmpty) {
      _case(scenario, background, tags, language, output);
      return;
    }
    for (final examples in scenario.examples) {
      final header = examples.tableHeader;
      if (header == null) {
        if (examples.tableBody.isNotEmpty) {
          throw const FormatException('Examples rows require a header.');
        }
        continue; // An empty Examples section defines no cases.
      }
      final tokens = _ExampleTokens(header.cells);
      for (final row in examples.tableBody) {
        tokens.validate(row);
        _case(
          scenario,
          background,
          tags.followedBy(examples.tags),
          language,
          output,
          tokens: tokens,
          row: row,
        );
      }
    }
  }

  void _case(
    messages.Scenario scenario,
    Iterable<messages.Step> background,
    Iterable<messages.Tag> tags,
    String language,
    List<messages.Envelope> output, {
    _ExampleTokens? tokens,
    messages.TableRow? row,
  }) {
    _budget._item(); // Reserve the case before constructing its children.
    final steps = <messages.PickleStep>[];
    var keyword = messages.StepKeywordType.unknown;
    if (scenario.steps.isNotEmpty) {
      for (final step in background) {
        keyword = _keyword(step, keyword);
        steps.add(_step(step, keyword));
      }
    }
    for (final step in scenario.steps) {
      keyword = _keyword(step, keyword);
      steps.add(_step(step, keyword, tokens: tokens, row: row));
    }
    final pickleTags = <messages.PickleTag>[];
    for (final tag in tags) {
      _budget._item();
      pickleTags.add(
        messages.PickleTag(name: _budget._literal(tag.name), astNodeId: tag.id),
      );
    }
    output.add(
      messages.Envelope(
        pickle: messages.Pickle(
          id: idGenerator(),
          uri: _budget._literal(uri),
          location: row?.location ?? scenario.location,
          name: _text(scenario.name, tokens, row),
          language: _budget._literal(language),
          steps: steps,
          tags: pickleTags,
          astNodeIds: [scenario.id, if (row != null) row.id],
        ),
      ),
    );
  }

  messages.StepKeywordType _keyword(
    messages.Step step,
    messages.StepKeywordType previous,
  ) =>
      step.keywordType == null ||
          step.keywordType == messages.StepKeywordType.conjunction
      ? previous
      : step.keywordType!;

  String _text(String value, _ExampleTokens? tokens, messages.TableRow? row) =>
      tokens == null || row == null
      ? _budget._literal(value)
      : tokens.render(value, row, _budget);

  messages.PickleStep _step(
    messages.Step step,
    messages.StepKeywordType keyword, {
    _ExampleTokens? tokens,
    messages.TableRow? row,
  }) {
    _budget._item();
    final table = step.dataTable;
    final doc = step.docString;
    final both = table != null && doc != null;
    final tableFirst = both && table.location.line < doc.location.line;
    messages.PickleTable? pickleTable;
    if (table != null) {
      final rows = <messages.PickleTableRow>[];
      for (final tableRow in table.rows) {
        _budget._item();
        final cells = <messages.PickleTableCell>[];
        for (final cell in tableRow.cells) {
          _budget._item();
          cells.add(
            messages.PickleTableCell(value: _text(cell.value, tokens, row)),
          );
        }
        rows.add(messages.PickleTableRow(cells: cells));
      }
      pickleTable = messages.PickleTable(
        argumentIndex: both ? (tableFirst ? 1 : 2) : null,
        rows: rows,
      );
    }
    final pickleDoc = doc == null
        ? null
        : messages.PickleDocString(
            argumentIndex: both ? (tableFirst ? 2 : 1) : null,
            mediaType: doc.mediaType == null
                ? null
                : _text(doc.mediaType!, tokens, row),
            content: _text(doc.content, tokens, row),
          );
    final type = switch (keyword) {
      messages.StepKeywordType.context => messages.PickleStepType.context,
      messages.StepKeywordType.action => messages.PickleStepType.action,
      messages.StepKeywordType.outcome => messages.PickleStepType.outcome,
      messages.StepKeywordType.unknown => messages.PickleStepType.unknown,
      messages.StepKeywordType.conjunction => null,
    };
    return messages.PickleStep(
      id: idGenerator(),
      text: _text(step.text, tokens, row),
      type: type,
      astNodeIds: [step.id, if (row != null) row.id],
      argument: pickleTable == null && pickleDoc == null
          ? null
          : messages.PickleStepArgument(
              dataTable: pickleTable,
              docString: pickleDoc,
            ),
    );
  }
}

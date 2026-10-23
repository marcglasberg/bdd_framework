part of 'bdd_base.dart';

/// Adds the public `.example(...)` DSL entrypoint to fluent BDD nodes that are
/// allowed to attach an `Examples` block.
///
/// This mixin is intended for end-of-chain nodes in the `Then` family, such as
/// [BddThen], [_ThenCode], [BddThenTable], and [BddExample] itself. The actual
/// storage of the example rows remains owned by [BddFramework].
mixin BddExampleAttachable on _BaseTerm {
  /// Adds a single example row to the current BDD and returns the shared
  /// [BddExample] block for continued chaining.
  ///
  /// The first value is required so that an example row can never be empty via
  /// the public DSL. Remaining values are optional and will be ignored when
  /// `null`.
  BddExample example(
    val v1, [
    val? v2,
    val? v3,
    val? v4,
    val? v5,
    val? v6,
    val? v7,
    val? v8,
    val? v9,
    val? v10,
    val? v11,
    val? v12,
    val? v13,
    val? v14,
    val? v15,
  ]) =>
      bdd.addExampleValues([
        v1,
        v2,
        v3,
        v4,
        v5,
        v6,
        v7,
        v8,
        v9,
        v10,
        v11,
        v12,
        v13,
        v14,
        v15,
      ].nonNulls.toList());
}

/// Represents a Gherkin Examples block which turns a Scenario into a
/// Scenario Outline and provides one or more rows of example values.
class BddExample extends BddTerm with BddRunnable, BddExampleAttachable {
  /// Creates a [BddExample] block with its first example row.
  ///
  /// The provided [values] are stored as a single row. Each subsequent call to
  /// [appendExampleValues] adds another row to the same `Examples` block.
  BddExample(BddFramework bdd, List<val> values)
      : super(bdd, '', _Variation.term) {
    rows.add(values.toSet());
  }

  /// The example rows associated with this `Examples` block.
  ///
  /// Each set represents one example row. Values are keyed later by their
  /// [val.name] when exposed through `ctx.example`.
  final List<Set<val>> rows = [];

  /// Formats the example rows as a Gherkin table using the provided [config].
  ///
  /// Column widths are derived from the widest header/value pair in each
  /// column so the rendered `Examples` table is aligned consistently.
  String formatExampleTable(BddConfig config) {
    Map<String, int> sizes = {};
    for (Set<val> row in rows) {
      for (val value in row) {
        int? maxValue1 = sizes[value.name];
        int maxValue2 = max(_escapeCell(value.name).length,
            _escapeCell(value.toString(config)).length);
        int maxValue =
            (maxValue1 == null) ? maxValue2 : max(maxValue1, maxValue2);

        sizes[value.name] = maxValue;
      }
    }

    var spaces = config.spaces;
    var space = config.space;
    var endOfLineChar = config.endOfLineChar;
    var tableDivider = config.tableDivider;

    String rightAlignPadding = spaces +
        spaces +
        spaces +
        ((config.rightAlignKeywords) ? config.padChar * 4 : '');

    String header = rightAlignPadding +
        '$tableDivider$space' +
        rows.first.map((val) {
          int length = sizes[val.name] ?? 50;
          return _escapeCell(val.name).padRight(length, space);
        }).join('$space$tableDivider$space') +
        '$space$tableDivider';

    List<String> rowsStr = rows.map((row) {
      return rightAlignPadding +
          '$tableDivider$space' +
          row.map((val) {
            int length = sizes[val.name] ?? 50;
            return _escapeCell(val.toString(config)).padRight(length, space);
          }).join('$space$tableDivider$space') +
          '$space$tableDivider';
    }).toList();

    return '$header$endOfLineChar${rowsStr.join(endOfLineChar)}';
  }

  /// The indentation used for the `Examples` block.
  @override
  String spaces(BddConfig config) => config.spaces + config.spaces;

  /// The keyword rendered for this block, usually `Examples:`.
  @override
  String keyword(BddConfig config) =>
      _keywordVariation(config) ?? config.keywords.examples;

  /// The configured prefix rendered before the `Examples` keyword.
  @override
  String keywordPrefix(BddConfig config) =>
      _keywordPrefixVariation(config) ?? config.keywordPrefix.examples;

  /// The configured suffix rendered after the `Examples` keyword.
  @override
  String keywordSuffix(BddConfig config) =>
      _keywordSuffixVariation(config) ?? config.keywordSuffix.examples;

  /// The configured content prefix for the `Examples` block.
  @override
  String prefix(BddConfig config) =>
      _prefixVariation(config) ?? config.prefix.examples;

  /// The configured content suffix for the `Examples` block.
  @override
  String suffix(BddConfig config) =>
      _suffixVariation(config) ?? config.suffix.examples;

  /// Appends one more example row to this `Examples` block.
  ///
  /// This is an internal append-style operation used by [BddFramework] when
  /// multiple `.example(...)` calls target the same scenario outline.
  BddExample appendExampleValues(List<val> values) {
    assert(values.isNotEmpty, 'Examples require at least one value.');
    rows.add(values.toSet());
    return this;
  }

  /// Runs the owning BDD in test mode with the given [reporter].
  ///
  /// This testing-only helper mirrors the behavior of other end-of-chain BDD
  /// nodes and returns the underlying [BddFramework] for inspection.
  @visibleForTesting
  BddFramework testRun(CodeRun code, BddReporter reporter) {
    _TestRun(code, reporter).run(bdd);
    return bdd;
  }

  /// Renders the full `Examples` block as Gherkin text.
  ///
  /// The output contains the keyword line followed by the formatted example
  /// table built from [rows].
  @override
  String toString([BddConfig config = BddConfig._default]) =>
      keywordPrefix(config) +
      spaces(config) +
      _keyword(config) +
      keywordSuffix(config) +
      ' ' +
      prefix(config) +
      config.endOfLineChar +
      formatExampleTable(config) +
      suffix(config);
}

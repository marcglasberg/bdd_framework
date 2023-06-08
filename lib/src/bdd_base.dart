import 'dart:async';
import 'dart:core';
import 'dart:io';
import 'dart:math';

import 'package:characters/characters.dart';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import "package:flutter_test/flutter_test.dart";
import "package:meta/meta.dart";

import 'bdd_context.dart';

/// This interface helps you format values in Examples and Tables.
/// If a value implements the [BddDescribe] interface, or if it has a
/// [describe] method, it will be used to format the value.
abstract class BddDescribe {
  Object? describe();
}

@isTest
BddFramework Bdd([BddFeature? feature]) => BddFramework(feature);

class row {
  final List<val> values;

  row(
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
    val? v16,
  ]) : values = [v1, v2, v3, v4, v5, v6, v7, v8, v9, v10, v11, v12, v13, v14, v15, v16]
            .whereNotNull()
            .toList();
}

class val {
  late String name;
  late Object? value;

  val(this.name, this.value);

  /// These 3 steps will be applied to format a value in Examples and Tables:
  ///
  /// 1) If a [BddConfig.transformDescribe] was provided, it will be used to format the value.
  ///
  /// 2) Next, if the value implements the [BddDescribe] interface, or if it has a
  /// [describe] method, it will be used to format the value.
  ///
  /// 3) Last, we'll call the value's [toString] method.
  ///
  @override
  String toString([BddConfig config = BddConfig._default]) {
    //
    dynamic _value = value;

    // 1)
    if ((config.transformDescribe != null)) {
      _value = config.transformDescribe!(value) ?? _value;
    }

    try {
      // The `describe` method here is dynamic.
      return _value.describe().toString();
    } on NoSuchMethodError {
      return _value.toString();
    }
  }
}

class BddKeywords {
  //
  const BddKeywords({
    this.feature = 'Feature:',
    this.scenario = 'Scenario:',
    this.scenarioOutline = 'Scenario Outline:',
    this.given = 'Given',
    this.when = 'When',
    this.then = 'Then',
    this.and = 'And',
    this.but = 'But',
    this.comment = '#',
    this.examples = 'Examples:',
    this.table = '',
  });

  const BddKeywords.only({
    this.feature = '',
    this.scenario = '',
    this.scenarioOutline = '',
    this.given = '',
    this.when = '',
    this.then = '',
    this.and = '',
    this.but = '',
    this.comment = '',
    this.examples = '',
    this.table = '',
  });

  static const empty = const BddKeywords.only();

  final String feature,
      scenario,
      scenarioOutline,
      given,
      when,
      then,
      and,
      but,
      comment,
      examples,
      table;
}

class BddConfig {
  static const _default = BddConfig();

  const BddConfig({
    this.keywords = const BddKeywords(),
    this.prefix = BddKeywords.empty,
    this.suffix = BddKeywords.empty,
    this.keywordPrefix = BddKeywords.empty,
    this.keywordSuffix = BddKeywords.empty,
    this.indent = 2,
    this.rightAlignKeywords = false,
    this.padChar = ' ',
    this.endOfLineChar = '\n',
    this.tableDivider = '|',
    this.space = ' ',
    this.transformDescribe,
  });

  /// The keywords themselves.
  final BddKeywords keywords;

  /// The [prefix] is after the keywords and before the term.
  /// The [suffix] is after the term.
  final BddKeywords prefix, suffix;

  /// The [keywordPrefix] is before the keyword.
  /// The [keywordSuffix] is after the keyword.
  final BddKeywords keywordPrefix, keywordSuffix;

  final int indent;
  final bool rightAlignKeywords;
  final String padChar;
  final String endOfLineChar;
  final String tableDivider;
  final String space;

  /// In tables and examples the output of values to feature files is done with toString().
  /// However, this can be overridden here for your business classes.
  /// Note: If you return `null` the values won't be changed.
  /// Example:
  ///
  /// ```
  /// Object? transformDescribe(Object? obj) {
  //   if (obj is User) return obj.userName;
  // }
  /// ```
  final Object? Function(Object?)? transformDescribe;

  String get spaces => padChar * indent;
}

abstract class _BaseTerm {
  final BddFramework bdd;

  _BaseTerm(this.bdd) {
    bdd.terms.add(this);
  }
}

enum _Variation { term, and, but, note }

abstract class BddTerm extends _BaseTerm {
  //
  final String text;
  final _Variation variation;

  BddTerm(BddFramework bdd, this.text, this.variation) : super(bdd);

  String spaces(BddConfig config);

  String keyword(BddConfig config);

  String keywordPrefix(BddConfig config);

  String keywordSuffix(BddConfig config);

  String prefix(BddConfig config);

  String suffix(BddConfig config);

  String? _keywordVariation(BddConfig config) => (variation == _Variation.and)
      ? config.keywords.and
      : (variation == _Variation.but)
          ? config.keywords.but
          : (variation == _Variation.note)
              ? config.keywords.comment
              : null;

  String? _keywordPrefixVariation(BddConfig config) => (variation == _Variation.and)
      ? config.keywordPrefix.and
      : (variation == _Variation.but)
          ? config.keywordPrefix.but
          : (variation == _Variation.note)
              ? config.keywordPrefix.comment
              : null;

  String? _keywordSuffixVariation(BddConfig config) => (variation == _Variation.and)
      ? config.keywordSuffix.and
      : (variation == _Variation.but)
          ? config.keywordSuffix.but
          : (variation == _Variation.note)
              ? config.keywordSuffix.comment
              : null;

  String? _prefixVariation(BddConfig config) => (variation == _Variation.and)
      ? config.prefix.and
      : (variation == _Variation.but)
          ? config.prefix.but
          : (variation == _Variation.note)
              ? config.prefix.comment
              : null;

  String? _suffixVariation(BddConfig config) => (variation == _Variation.and)
      ? config.suffix.and
      : (variation == _Variation.but)
          ? config.suffix.but
          : (variation == _Variation.note)
              ? config.suffix.comment
              : null;

  int _padSize(BddConfig config) {
    return max(
      max(
        max(
          max(config.keywords.given.length, config.keywords.then.length),
          config.keywords.when.length,
        ),
        config.keywords.and.length,
      ),
      config.keywords.but.length,
    );
  }

  String _keyword([BddConfig config = BddConfig._default]) {
    var term = keyword(config);
    String result = _keyword_unpadded(term, config);
    if (config.rightAlignKeywords) {
      int padSize = _padSize(config);
      result = result.padLeft(padSize, config.padChar);
    }
    return result;
  }

  String _keyword_unpadded(String term, BddConfig config) {
    if (variation == _Variation.term)
      return term;
    else if (variation == _Variation.and)
      return config.keywords.and;
    else if (variation == _Variation.but)
      return config.keywords.but;
    else if (variation == _Variation.note)
      return config.keywords.comment;
    else
      throw AssertionError(variation);
  }

  String _capitalize(String text) {
    if (variation == _Variation.note) {
      var characters = Characters(text);
      return (characters.take(1).toUpperCase() + characters.skip(1)).string;
    } else
      return text;
  }

  @override
  String toString([BddConfig config = BddConfig._default]) =>
      keywordPrefix(config) +
      spaces(config) +
      _keyword(config) +
      keywordSuffix(config) +
      ' ' +
      prefix(config) +
      _capitalize(text) +
      suffix(config);
}

abstract class BddCodeTerm extends _BaseTerm {
  final CodeRun codeRun;

  BddCodeTerm(BddFramework bdd, this.codeRun) : super(bdd);
}

class BddFramework {
  //
  final BddFeature? feature;
  final List<_BaseTerm> terms;
  Duration? _timeout;
  TestRunConfig? _config;
  bool _skip;
  final List<CodeRun> codeRuns;

  /// Nulls means the test was not run yet.
  /// True means it passed.
  /// False means it did not pass.
  List<bool> passed;

  BddFramework([this.feature])
      : terms = [],
        _timeout = null,
        _skip = false,
        codeRuns = [],
        passed = [];

  void addCode(CodeRun code) => codeRuns.add(code);

  /// Example: `List<Given> = bdd.allTerms<Given>().toList();`
  Iterable<T> allTerms<T extends BddTerm>() => terms.whereType<T>();

  /// The BDD description is its Scenario (or blank if there is no Scenario).
  String description() => allTerms<BddScenario>().firstOrNull?.text ?? "";

  /// A Bdd may have 0 or 1 examples.
  BddExample? example() => allTerms<BddExample>().firstOrNull;

  /// A Bdd may have 0, 1, or more tables (which are not examples).
  List<BddTableTerm> tables() => allTerms<BddTableTerm>().where((t) => t is! BddExample).toList();

  /// The example, if it exists, may have any number of rows.
  Set<val>? exampleRow(int? count) => (count == null) ? null : example()?.rows[count];

  int numberOfExamples() {
    BddExample? _example = example();
    return (_example == null) ? 0 : _example.rows.length;
  }

  /// Skips running this test.
  BddFramework get skip {
    _skip = true;
    return this;
  }

  /// Skips running this test in REAL mode (runs only in simulated mode).
  BddFramework get skipReal {
    // TODO: MARCELO
    // _skip = true;
    return this;
  }

  BddFramework timeout(Duration? duration) {
    _timeout = duration;
    return this;
  }

  // BddFramework config(Config? config) {
  //   _config = config;
  //   return this;
  // }

  // BddFramework configFrom({
  //   String? testOn,
  //   Timeout? timeout,
  //   dynamic tags,
  //   Map<String, dynamic>? onPlatform,
  //   int? retry,
  // }) =>
  //     config(Config(
  //         testOn: testOn, timeout: timeout, tags: tags, onPlatform: onPlatform, retry: retry));

  BddFramework timeoutSec(int seconds) => timeout(Duration(seconds: seconds));

  BddScenario scenario(String text) => BddScenario(this, text);

  BddGiven given(String text) => BddGiven(this, text);

  Iterable<BddTerm> get textTerms => terms.whereType<BddTerm>();

  Iterable<BddCodeTerm> get codeTerms => terms.whereType<BddCodeTerm>();

  List<String> toMap(BddConfig config) {
    List<String> result = [];

    for (BddTerm term in textTerms) {
      result.add(term.toString(config));
    }

    return result;
  }

  @override
  String toString({
    BddConfig config = BddConfig._default,
    bool withFeature = false,
  }) =>
      (withFeature ? feature?.toString(config) ?? "" : "") +
      toMap(config).join(config.endOfLineChar) +
      config.endOfLineChar;
}

class BddScenario extends BddTerm {
  BddScenario(BddFramework bdd, String text) : super(bdd, text, _Variation.term);

  bool get containsExample => bdd.terms.any((term) => term is BddExample);

  @override
  String spaces(BddConfig config) => config.spaces;

  @override
  String keyword(BddConfig config) => containsExample //
      ? config.keywords.scenarioOutline
      : config.keywords.scenario;

  @override
  String keywordPrefix(BddConfig config) => containsExample //
      ? config.keywordPrefix.scenarioOutline
      : config.keywordPrefix.scenario;

  @override
  String keywordSuffix(BddConfig config) => containsExample //
      ? config.keywordSuffix.scenarioOutline
      : config.keywordSuffix.scenario;

  @override
  String prefix(BddConfig config) => containsExample //
      ? config.prefix.scenarioOutline
      : config.prefix.scenario;

  @override
  String suffix(BddConfig config) => containsExample //
      ? config.suffix.scenarioOutline
      : config.suffix.scenario;

  BddGiven given(String text) => BddGiven(bdd, text);

  BddGiven note(String text) => BddGiven._(bdd, text, _Variation.note);

  @override
  // ignore: unnecessary_overrides
  String toString([BddConfig config = BddConfig._default]) => super.toString(config);
}

class BddGiven extends BddTerm {
  BddGiven(BddFramework bdd, String text) : super(bdd, text, _Variation.term);

  BddGiven._(BddFramework bdd, String text, _Variation variation) : super(bdd, text, variation);

  @override
  String spaces(BddConfig config) => config.spaces + config.spaces;

  @override
  String keyword(BddConfig config) => _keywordVariation(config) ?? config.keywords.given;

  @override
  String keywordPrefix(BddConfig config) =>
      _keywordPrefixVariation(config) ?? config.keywordPrefix.given;

  @override
  String keywordSuffix(BddConfig config) =>
      _keywordSuffixVariation(config) ?? config.keywordSuffix.given;

  @override
  String prefix(BddConfig config) => _prefixVariation(config) ?? config.prefix.given;

  @override
  String suffix(BddConfig config) => _suffixVariation(config) ?? config.suffix.given;

  /// A table must have a name and rows. The name is necessary if you want to read the values from
  /// it later (if not, just pass an empty string).
  /// Example: `ctx.table('notifications').row(0).val('read') as bool`.
  BddGivenTable table(
    String tableName,
    row row1, [
    row? row2,
    row? row3,
    row? row4,
    row? row5,
    row? row6,
    row? row7,
    row? row8,
    row? row9,
    row? row10,
    row? row11,
    row? row12,
    row? row13,
    row? row14,
    row? row15,
    row? row16,
  ]) =>
      BddGivenTable(bdd, tableName, row1, row2, row3, row4, row5, row6, row7, row8, row9, row10,
          row11, row12, row13, row14, row15, row16);

  BddGiven and(String text) => BddGiven._(bdd, text, _Variation.and);

  BddGiven but(String text) => BddGiven._(bdd, text, _Variation.but);

  BddGiven note(String text) => BddGiven._(bdd, text, _Variation.note);

  BddWhen when(String text) => BddWhen(bdd, text);

  BddThen then(String text) => BddThen(bdd, text);

  _GivenCode code(CodeRun code) => _GivenCode(bdd, code);

  @override
  // ignore: unnecessary_overrides
  String toString([BddConfig config = BddConfig._default]) => super.toString(config);
}

class _GivenCode extends BddCodeTerm {
  _GivenCode(BddFramework bdd, CodeRun code) : super(bdd, code);

  /// A table must have a name and rows. The name is necessary if you want to read the values from
  /// it later (if not, just pass an empty string).
  /// Example: `ctx.table('notifications').row(0).val('read') as bool`.
  BddGivenTable table(String tableName, row row1, [row? row2, row? row3, row? row4]) =>
      BddGivenTable(bdd, tableName, row1, row2, row3, row4);

  BddGiven and(String text) => BddGiven._(bdd, text, _Variation.and);

  BddGiven but(String text) => BddGiven._(bdd, text, _Variation.but);

  BddGiven note(String text) => BddGiven._(bdd, text, _Variation.note);

  BddWhen when(String text) => BddWhen(bdd, text);

  _GivenCode code(CodeRun code) => _GivenCode(bdd, code);
}

class BddWhen extends BddTerm {
  BddWhen(BddFramework bdd, String text) : super(bdd, text, _Variation.term);

  BddWhen._(BddFramework bdd, String text, _Variation variation) : super(bdd, text, variation);

  @override
  String spaces(BddConfig config) => config.spaces + config.spaces;

  @override
  String keyword(BddConfig config) => _keywordVariation(config) ?? config.keywords.when;

  @override
  String keywordPrefix(BddConfig config) =>
      _keywordPrefixVariation(config) ?? config.keywordPrefix.when;

  @override
  String keywordSuffix(BddConfig config) =>
      _keywordSuffixVariation(config) ?? config.keywordSuffix.when;

  @override
  String prefix(BddConfig config) => _prefixVariation(config) ?? config.prefix.when;

  @override
  String suffix(BddConfig config) => _suffixVariation(config) ?? config.suffix.when;

  /// A table must have a name and rows. The name is necessary if you want to read the values from
  /// it later (if not, just pass an empty string).
  /// Example: `ctx.table('notifications').row(0).val('read') as bool`.
  BddWhenTable table(String tableName, row row1, [row? row2, row? row3, row? row4]) =>
      BddWhenTable(bdd, tableName, row1, row2, row3, row4);

  BddWhen and(String text) => BddWhen._(bdd, text, _Variation.and);

  BddWhen but(String text) => BddWhen._(bdd, text, _Variation.but);

  BddWhen note(String text) => BddWhen._(bdd, text, _Variation.note);

  BddThen then(String text) => BddThen(bdd, text);

  _WhenCode code(CodeRun code) => _WhenCode(bdd, code);

  void run(CodeRun code) => _Run().run(bdd, code);

  @override
  // ignore: unnecessary_overrides
  String toString([BddConfig config = BddConfig._default]) => super.toString(config);
}

class _WhenCode extends BddCodeTerm {
  _WhenCode(BddFramework bdd, CodeRun code) : super(bdd, code);

  /// A table must have a name and rows. The name is necessary if you want to read the values from
  /// it later (if not, just pass an empty string).
  /// Example: `ctx.table('notifications').row(0).val('read') as bool`.
  BddWhenTable table(String tableName, row row1, [row? row2, row? row3, row? row4]) =>
      BddWhenTable(bdd, tableName, row1, row2, row3, row4);

  BddWhen and(String text) => BddWhen._(bdd, text, _Variation.and);

  BddWhen but(String text) => BddWhen._(bdd, text, _Variation.but);

  BddWhen note(String text) => BddWhen._(bdd, text, _Variation.note);

  BddThen then(String text) => BddThen(bdd, text);

  _WhenCode code(CodeRun code) => _WhenCode(bdd, code);
}

class BddThen extends BddTerm {
  BddThen(BddFramework bdd, String text) : super(bdd, text, _Variation.term);

  BddThen._(BddFramework bdd, String text, _Variation variation) : super(bdd, text, variation);

  @override
  String spaces(BddConfig config) => config.spaces + config.spaces;

  @override
  String keyword(BddConfig config) => _keywordVariation(config) ?? config.keywords.then;

  @override
  String keywordPrefix(BddConfig config) =>
      _keywordPrefixVariation(config) ?? config.keywordPrefix.then;

  @override
  String keywordSuffix(BddConfig config) =>
      _keywordSuffixVariation(config) ?? config.keywordSuffix.then;

  @override
  String prefix(BddConfig config) => _prefixVariation(config) ?? config.prefix.then;

  @override
  String suffix(BddConfig config) => _suffixVariation(config) ?? config.suffix.then;

  /// A table must have a name and rows. The name is necessary if you want to read the values from
  /// it later (if not, just pass an empty string).
  /// Example: `ctx.table('notifications').row(0).val('read') as bool`.
  BddThenTable table(String tableName, row row1, [row? row2, row? row3, row? row4]) =>
      BddThenTable(bdd, tableName, row1, row2, row3, row4);

  BddThen and(String text) => BddThen._(bdd, text, _Variation.and);

  BddThen but(String text) => BddThen._(bdd, text, _Variation.but);

  BddThen note(String text) => BddThen._(bdd, text, _Variation.note);

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
      BddExample(bdd, v1, v2, v3, v4, v5, v6, v7, v8, v9, v10, v11, v12, v13, v14, v15);

  _ThenCode code(CodeRun code) => _ThenCode(bdd, code);

  void run(CodeRun code) => _Run().run(bdd, code);

  @visibleForTesting
  BddFramework testRun(CodeRun code, BddReporter reporter) {
    _TestRun(code, reporter).run(bdd);
    return bdd;
  }

  @override
  // ignore: unnecessary_overrides
  String toString([BddConfig config = BddConfig._default]) => super.toString(config);
}

class _ThenCode extends BddCodeTerm {
  _ThenCode(BddFramework bdd, CodeRun code) : super(bdd, code);

  /// A table must have a name and rows. The name is necessary if you want to read the values from
  /// it later (if not, just pass an empty string).
  /// Example: `ctx.table('notifications').row(0).val('read') as bool`.
  BddThenTable table(String tableName, row row1, [row? row2, row? row3, row? row4]) =>
      BddThenTable(bdd, tableName, row1, row2, row3, row4);

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
      BddExample(bdd, v1, v2, v3, v4, v5, v6, v7, v8, v9, v10, v11, v12, v13, v14, v15);

  BddWhen and(String text) => BddWhen._(bdd, text, _Variation.and);

  BddWhen but(String text) => BddWhen._(bdd, text, _Variation.but);

  BddWhen note(String text) => BddWhen._(bdd, text, _Variation.note);

  _ThenCode code(CodeRun code) => _ThenCode(bdd, code);

  void run(CodeRun code) => _Run().run(bdd, code);

  @visibleForTesting
  BddFramework testRun(CodeRun code, BddReporter reporter) {
    _TestRun(code, reporter).run(bdd);
    return bdd;
  }
}

abstract class BddTableTerm extends BddTerm {
  //
  final String tableName;

  final List<row> rows = [];

  BddTableTerm(BddFramework bdd, this.tableName) : super(bdd, '', _Variation.term);

  void run(CodeRun code) => _Run().run(bdd, code);

  /// Here we have something like:
  /// [
  /// { (number;123), (password;ABC) }
  /// { (number;456), (password;XYZ) }
  /// ]
  String formatTable(BddConfig config) {
    //
    Map<String, int> sizes = {};
    for (row _row in rows) {
      //
      for (val value in _row.values) {
        int? maxValue1 = sizes[value.name];
        int maxValue2 = max(value.name.length, value.toString(config).length);
        int maxValue = (maxValue1 == null) ? maxValue2 : max(maxValue1, maxValue2);

        sizes[value.name] = maxValue;
      }
    }

    var spaces = config.spaces;
    var space = config.space;
    var endOfLineChar = config.endOfLineChar;
    var tableDivider = config.tableDivider;

    String rightAlignPadding =
        spaces + spaces + spaces + ((config.rightAlignKeywords) ? config.padChar * 4 : '');

    String header = rightAlignPadding +
        '$tableDivider$space' +
        rows.first.values.map((val) {
          int length = sizes[val.name] ?? 50;
          return val.name.padRight(length, space);
        }).join('$space$tableDivider$space') +
        '$space$tableDivider';

    List<String> rowsStr = rows.map((row) {
      return rightAlignPadding +
          '$tableDivider$space' +
          row.values.map((val) {
            int length = sizes[val.name] ?? 50;
            return val.toString(config).padRight(length, space);
          }).join('$space$tableDivider$space') +
          '$space$tableDivider';
    }).toList();

    var result = '$header$endOfLineChar'
        '${rowsStr.join(endOfLineChar)}';

    return result;
  }

  @override
  String spaces(BddConfig config) => '';

  @override
  String keyword(BddConfig config) => config.keywords.table;

  @override
  String keywordPrefix(BddConfig config) => config.keywordPrefix.table;

  @override
  String keywordSuffix(BddConfig config) => config.keywordSuffix.table;

  @override
  String prefix(BddConfig config) => config.prefix.table;

  @override
  String suffix(BddConfig config) => config.suffix.table;

  /// Tables have a special toString treatment.
  @override
  String toString([BddConfig config = BddConfig._default]) =>
      keywordPrefix(config) +
      keyword(config) +
      keywordSuffix(config) +
      prefix(config) +
      formatTable(config) +
      suffix(config);
}

class BddExample extends BddTerm {
  //
  BddExample(BddFramework bdd, val v1, val? v2, val? v3, val? v4, val? v5, val? v6, val? v7,
      val? v8, val? v9, val? v10, val? v11, val? v12, val? v13, val? v14, val? v15)
      : super(bdd, '', _Variation.term) {
    var set =
        [v1, v2, v3, v4, v5, v6, v7, v8, v9, v10, v11, v12, v13, v14, v15].whereNotNull().toSet();
    rows.add(set);
  }

  final List<Set<val>> rows = [];

  void run(CodeRun code) => _Run().run(bdd, code);

  /// Here we have something like:
  /// [
  /// { (number;123), (password;ABC) }
  /// { (number;456), (password;XYZ) }
  /// ]
  String formatExampleTable(BddConfig config) {
    //
    Map<String, int> sizes = {};
    for (Set<val> row in rows) {
      //
      for (val value in row) {
        int? maxValue1 = sizes[value.name];
        int maxValue2 = max(value.name.length, value.toString(config).length);
        int maxValue = (maxValue1 == null) ? maxValue2 : max(maxValue1, maxValue2);

        sizes[value.name] = maxValue;
      }
    }

    var spaces = config.spaces;
    var space = config.space;
    var endOfLineChar = config.endOfLineChar;
    var tableDivider = config.tableDivider;

    String rightAlignPadding =
        spaces + spaces + spaces + ((config.rightAlignKeywords) ? config.padChar * 4 : '');

    String header = rightAlignPadding +
        '$tableDivider$space' +
        rows.first.map((val) {
          int length = sizes[val.name] ?? 50;
          return val.name.padRight(length, space);
        }).join('$space$tableDivider$space') +
        '$space$tableDivider';

    List<String> rowsStr = rows.map((row) {
      return rightAlignPadding +
          '$tableDivider$space' +
          row.map((val) {
            int length = sizes[val.name] ?? 50;
            return val.toString(config).padRight(length, space);
          }).join('$space$tableDivider$space') +
          '$space$tableDivider';
    }).toList();

    var result = '$header$endOfLineChar'
        '${rowsStr.join(endOfLineChar)}';

    return result;
  }

  // @override
  // String spaces(BddConfig config) => '';
  //
  // @override
  // String keyword(BddConfig config) => config.keywords.table;
  //
  // @override
  // String keywordPrefix(BddConfig config) => config.keywordPrefix.table;
  //
  // @override
  // String keywordSuffix(BddConfig config) => config.keywordSuffix.table;
  //
  // @override
  // String prefix(BddConfig config) => config.prefix.table;
  //
  // @override
  // String suffix(BddConfig config) => config.suffix.table;

  // /// Tables have a special toString treatment.
  // @override
  // String toString([BddConfig config = BddConfig._default]) =>
  //     keywordPrefix(config) +
  //         keyword(config) +
  //         keywordSuffix(config) +
  //         prefix(config) +
  //         formatExampleTable(config) +
  //         suffix(config);

  @override
  String spaces(BddConfig config) => config.spaces + config.spaces;

  @override
  String keyword(BddConfig config) => _keywordVariation(config) ?? config.keywords.examples;

  @override
  String keywordPrefix(BddConfig config) =>
      _keywordPrefixVariation(config) ?? config.keywordPrefix.examples;

  @override
  String keywordSuffix(BddConfig config) =>
      _keywordSuffixVariation(config) ?? config.keywordSuffix.examples;

  @override
  String prefix(BddConfig config) => _prefixVariation(config) ?? config.prefix.examples;

  @override
  String suffix(BddConfig config) => _suffixVariation(config) ?? config.suffix.examples;

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
  ]) {
    rows.add(
        [v1, v2, v3, v4, v5, v6, v7, v8, v9, v10, v11, v12, v13, v14, v15].whereNotNull().toSet());
    return this;
  }

  @visibleForTesting
  BddFramework testRun(CodeRun code, BddReporter reporter) {
    _TestRun(code, reporter).run(bdd);
    return bdd;
  }

  /// Examples have a special toString treatment.
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

class BddGivenTable extends BddTableTerm {
  //
  BddGivenTable(
    BddFramework bdd,
    String tableName,
    row row1, [
    row? row2,
    row? row3,
    row? row4,
    row? row5,
    row? row6,
    row? row7,
    row? row8,
    row? row9,
    row? row10,
    row? row11,
    row? row12,
    row? row13,
    row? row14,
    row? row15,
    row? row16,
  ]) : super(bdd, tableName) {
    rows.addAll([
      row1,
      row2,
      row3,
      row4,
      row5,
      row6,
      row7,
      row8,
      row9,
      row10,
      row11,
      row12,
      row13,
      row14,
      row15,
      row16
    ].whereNotNull());
  }

  BddGiven and(String text) => BddGiven._(bdd, text, _Variation.and);

  BddGiven but(String text) => BddGiven._(bdd, text, _Variation.but);

  BddGiven note(String text) => BddGiven._(bdd, text, _Variation.note);

  BddWhen when(String text) => BddWhen(bdd, text);

  _GivenCode code(CodeRun code) => _GivenCode(bdd, code);

  @override
  // ignore: unnecessary_overrides
  String toString([BddConfig config = BddConfig._default]) => super.toString(config);
}

class BddWhenTable extends BddTableTerm {
  //
  BddWhenTable(BddFramework bdd, String tableName, row row1, [row? row2, row? row3, row? row4])
      : super(bdd, tableName) {
    rows.addAll([row1, row2, row3, row4].whereNotNull());
  }

  BddWhen and(String text) => BddWhen._(bdd, text, _Variation.and);

  BddWhen but(String text) => BddWhen._(bdd, text, _Variation.but);

  BddWhen note(String text) => BddWhen._(bdd, text, _Variation.note);

  BddThen then(String text) => BddThen(bdd, text);

  _WhenCode code(CodeRun code) => _WhenCode(bdd, code);

  @override
  // ignore: unnecessary_overrides
  String toString([BddConfig config = BddConfig._default]) => super.toString(config);
}

class BddThenTable extends BddTableTerm {
  //
  BddThenTable(BddFramework bdd, String tableName, row row1, [row? row2, row? row3, row? row4])
      : super(bdd, tableName) {
    rows.addAll([row1, row2, row3, row4].whereNotNull());
  }

  BddThen and(String text) => BddThen._(bdd, text, _Variation.and);

  BddThen but(String text) => BddThen._(bdd, text, _Variation.but);

  BddThen note(String text) => BddThen._(bdd, text, _Variation.note);

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
      BddExample(bdd, v1, v2, v3, v4, v5, v6, v7, v8, v9, v10, v11, v12, v13, v14, v15);

  _ThenCode code(CodeRun code) => _ThenCode(bdd, code);

  @override
  // ignore: unnecessary_overrides
  String toString([BddConfig config = BddConfig._default]) => super.toString(config);

  @override
  void run(CodeRun code) => _Run().run(bdd, code);

  @visibleForTesting
  BddFramework testRun(CodeRun code, BddReporter reporter) {
    _TestRun(code, reporter).run(bdd);
    return bdd;
  }
}

class TestResult {
  final BddFramework _bdd;

  TestResult(this._bdd);

  Iterable<BddTerm> get terms => _bdd.textTerms;

  List<String> toMap([BddConfig config = BddConfig._default]) => _bdd.toMap(config);

  @override
  String toString([BddConfig config = BddConfig._default]) => _bdd.toString(config: config);

  bool get wasSkipped => _bdd._skip;

  /// Empty means the test was not run yet.
  /// If the Bdd has no examples, the result will be a single value.
  /// Otherwise, it will have one result for each example.
  ///
  /// For each value:
  /// True values means it passed.
  /// False values means it did not pass.
  ///
  List<bool> get passed => _bdd.passed;
}

class BddFeature {
  final String title;
  final String? description;
  final List<BddFramework> _bdds;

  List<BddFramework> get bdds => _bdds.toList();

  bool get isEmpty => title.isEmpty;

  bool get isNotEmpty => title.isNotEmpty;

  BddFeature(this.title, {this.description}) : _bdds = [];

  List<TestResult> get testResults => _bdds.map((bdd) => TestResult(bdd)).toList();

  List<BddFramework> result = [];

  void add(BddFramework bdd) {
    _bdds.add(bdd);
  }

  @override
  String toString([BddConfig config = BddConfig._default]) {
    var result = config.keywordPrefix.feature +
        config.keywords.feature +
        config.keywordSuffix.feature +
        ' ' +
        config.prefix.feature +
        title +
        config.suffix.feature +
        config.endOfLineChar;

    if (description != null) {
      var parts = description!.trim().split('\n');
      result = result +
          config.spaces +
          config.prefix.feature +
          parts.join(config.endOfLineChar + config.spaces) +
          config.suffix.feature +
          config.endOfLineChar;
    }

    return result;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BddFeature && runtimeType == other.runtimeType && title == other.title;

  @override
  int get hashCode => title.hashCode;
}

/// Example:
///
/// ```
/// void main() async {
///   BddReporter.set(ConsoleReporter(), FeatureFileReporter());
///   group('favorites_test', favorites_test.main);
///   group('search_test', search_test.main);
///   await BddReporter.reportAll();
/// }
/// ```
///
abstract class BddReporter {
  //
  /// Subclasses must implement this.
  Future<void> report();

  static _RunInfo runInfo = _RunInfo();
  static final _emptyFeature = BddFeature("");
  static final List<BddReporter> _reporters = [];
  static bool ignoreOverflow = true;
  static const yellow = "\x1B[38;5;226m";
  static const reset = "\u001b[0m";

  static void set([
    BddReporter? r1,
    BddReporter? r2,
    BddReporter? r3,
    BddReporter? r4,
    BddReporter? r5,
  ]) {
    _reporters
      ..clear()
      ..addAll([r1, r2, r3, r4, r5].whereNotNull());
  }

  static Future<void> reportAll() async {
    tearDownAll(() async {
      stdout.writeln(yellow);
      stdout.writeln('RESULTS ══════════════════════════════════════════════');
      stdout.writeln('TOTAL: ${runInfo.totalTestCount} tests (${runInfo.testCount} BDDs)');
      stdout.writeln('PASSED: ${runInfo.passedCount} tests');
      stdout.writeln('FAILED: ${runInfo.failedCount} tests');
      stdout.writeln('SKIPPED: ${runInfo.skipCount} tests');
      stdout.writeln('══════════════════════════════════════════════════════$reset');
      stdout.writeln('\n');

      for (BddReporter _reporter in BddReporter._reporters) {
        stdout.writeln('Running the ${_reporter.runtimeType}...\n');
        await _reporter.report();
      }
    });
  }

  final Set<BddFeature> features = {};

  void _addBdd(BddFramework bdd) {
    //
    // Use the feature, if provided. Otherwise, use the "empty feature".
    var _feature = bdd.feature ?? _emptyFeature;

    // We must find out if we already have a feature with the given title.
    // If we do, use the one we already have.
    BddFeature? feature = features.firstWhereOrNull((feature) => feature.title == _feature.title);

    // If we don't, use the new one provided, and put it in the features set.
    if (feature == null) {
      feature = _feature;
      features.add(feature);
    }

    // Add the bdd to the feature.
    feature.add(bdd);
  }

  /// Keeps A-Z 0-9, make it lowercase, and change spaces into underline.
  String normalizeFileName(String name) =>
      name.trim().splitMapJoin(RegExp(r"""[ "'#<$+%>!`&*|{?=}/:\\@^.]"""),
          onMatch: (m) => m[0] == ' ' ? '_' : '', onNonMatch: (m) => m.toLowerCase());
}

class TestRunConfig {
  final String? testOn;
  final Timeout? timeout;
  final dynamic tags;
  final Map<String, dynamic>? onPlatform;
  final int? retry;

  TestRunConfig({this.testOn, this.timeout, this.tags, this.onPlatform, this.retry});
}

class _RunInfo {
  int totalTestCount = 0;
  int testCount = 0;
  int skipCount = 0;
  int passedCount = 0;
  int failedCount = 0;

  bool overflowIsSetUp = false;
}

typedef CodeRun = FutureOr<void> Function(BddContext ctx)?;

/// This will run with the global reporter/runInfo.
class _Run {
  //
  void run(BddFramework bdd, CodeRun code) {
    //
    // Add the code to the BDD, as a ThenCode.
    _ThenCode(bdd, code);

    BddReporter._reporters.forEach((_reporter) {
      _reporter._addBdd(bdd);
    });

    int numberOfExamples = bdd.numberOfExamples();

    BddReporter.runInfo.testCount++;

    if (numberOfExamples == 0)
      _runTheTest(bdd, null);
    else {
      for (int i = 0; i < numberOfExamples; i++) _runTheTest(bdd, i);
    }
  }

  static const BddConfig config = BddConfig(
    //
    keywords: BddKeywords(
      feature: '${boldItalic}Feature:$boldItalicOff',
      scenario: '${boldItalic}Scenario:$boldItalicOff',
      scenarioOutline: '${boldItalic}Scenario Outline:$boldItalicOff',
      given: '${boldItalic}Given$boldItalicOff',
      when: '${boldItalic}When$boldItalicOff',
      then: '${boldItalic}Then$boldItalicOff',
      and: '${boldItalic}And$boldItalicOff',
      but: '${boldItalic}But$boldItalicOff',
      comment: '$boldItalic#$boldItalicOff',
      examples: '${boldItalic}Examples:$boldItalicOff',
    ),
    //
    keywordPrefix: BddKeywords.only(
      scenario: '\n',
      scenarioOutline: '\n',
      given: '\n',
      when: '\n',
      then: '\n',
      examples: '\n',
      comment: grey,
    ),
    //
    suffix: BddKeywords.only(
      // given: "WHITE!",
      comment: blue,
    ),
    //
  );

  String subscript(int index) {
    String result = '';
    var x = index.toString();
    for (int i = 0; i < x.length; i++) {
      var char = x[i];
      result += {
        '0': '₀',
        '1': '₁',
        '2': '₂',
        '3': '₃',
        '4': '₄',
        '5': '₅',
        '6': '₆',
        '7': '₇',
        '8': '₈',
        '9': '₉'
      }[char]!;
    }
    return result;
  }

  ///  Returns something like: "4₁₂"
  String testCountStr(int testCount, int? exampleNumber) =>
      "$testCount${exampleNumber == null ? '' : '${subscript(exampleNumber + 1)}'}";

  /// If the Bdd has examples, this method will be called once for each example, with
  /// [exampleNumber] starting in 0.
  ///
  /// If the Bdd does NOT have examples, this method will run once, with [exampleNumber] null.
  ///
  void _runTheTest(BddFramework bdd, int? exampleNumber) {
    //
    BddReporter.runInfo.totalTestCount++;

    var totalRetries = bdd._config?.retry ?? 0;
    var currentExecution = 0;

    String bddStr = bdd.toString(config: config, withFeature: true);

    int testCount = BddReporter.runInfo.testCount;
    // int totalTestCount = runInfo.totalTestCount;

    if (bdd._skip) BddReporter.runInfo.skipCount++;

    String _testCountStr = testCountStr(testCount, exampleNumber);

    test(
      //
      '$_testCountStr ${bdd.description()}',
      //
      () async {
        if (BddReporter.ignoreOverflow) _ignoreOverflowErrors();

        currentExecution++;

        print((currentExecution == 1) //
            ? "${_header(bdd._skip, _testCountStr)}$blue$bddStr$boldOff"
            : "\n${red}Retry $currentExecution.\n$boldOff");

        final example = BddTableValues.from(bdd.exampleRow(exampleNumber));
        final tables = BddMultipleTableValues.from(bdd.tables());
        final ctx = BddContext(example, tables);

        try {
          /// Run all bdd code.
          for (CodeRun codeRun in bdd.codeTerms.map((BddCodeTerm codeTerm) => codeTerm.codeRun)) {
            await codeRun?.call(ctx);
          }
        } catch (error, stacktrace) {
          bdd.passed.add(false);
          BddReporter.runInfo.failedCount++;
          print("\n");
          registerException(error, stacktrace);
          print(_fail(_testCountStr));
          return;
        } finally {
          _cleanTargetPlatformOverride();
        }

        bdd.passed.add(true);
        BddReporter.runInfo.passedCount++;
        print(_footer(_testCountStr));
      },
      //
      timeout: Timeout(bdd._timeout),
      skip: bdd._skip,
      tags: bdd._config?.tags,
      onPlatform: bdd._config?.onPlatform,
      retry: totalRetries,
      testOn: bdd._config?.testOn,
    );
  }

  // static const white = "\x1B[38;5;255m";
  // static const reversed = "\u001b[7m";
  static const red = "\x1B[38;5;9m";
  static const blue = "\x1B[38;5;45m";
  static const yellow = "\x1B[38;5;226m";
  static const grey = "\x1B[38;5;246m";
  static const bold = "\u001b[1m";
  static const italic = "\u001b[3m";
  static const boldItalic = bold + italic;
  static const boldItalicOff = boldOff + italicOff;
  static const boldOff = "\u001b[22m";
  static const italicOff = "\u001b[23m";
  static const reset = "\u001b[0m";

  // See ANSI Colors here: https://pub.dev/packages/ansicolor
  String _header(bool skip, String testNumberStr) {
    return yellow +
        italic +
        "TEST $testNumberStr ${skip ? "SKIPPED" : ""} "
            "$italicOff══════════════════════════════════════════════════$reset\n\n";
  }

  String _footer(String testNumberStr) =>
      grey + "\n✔ ${italic}TEST $testNumberStr PASSED!\n\n" + italicOff;

  String _fail(String testNumberStr) =>
      grey + "\n⚠ ${italic}TEST $testNumberStr FAILED!\n" + italicOff;
}

/// This is for testing the BDD framework only.
class _TestRun {
  final CodeRun code;
  final BddReporter? reporter;

  @visibleForTesting
  _TestRun(this.code, this.reporter);

  void run(BddFramework bdd) {
    //
    // Add the code to the BDD, as a ThenCode.
    _ThenCode(bdd, code);

    reporter?._addBdd(bdd);

    int numberOfExamples = bdd.numberOfExamples();

    if (numberOfExamples == 0)
      _runTheTest(bdd, null);
    else {
      for (int i = 0; i < numberOfExamples; i++) _runTheTest(bdd, i);
    }
  }

  void _runTheTest(BddFramework bdd, int? exampleNumber) {
    //
    final example = BddTableValues.from(bdd.exampleRow(exampleNumber));
    final tables = BddMultipleTableValues.from(bdd.tables());
    final ctx = BddContext(example, tables);

    if (!bdd._skip)
      try {
        /// Run all bdd code.
        Iterable<CodeRun> codeRuns = bdd.codeTerms.map((BddCodeTerm codeTerm) => codeTerm.codeRun);
        for (CodeRun codeRun in codeRuns) {
          codeRun?.call(ctx);
        }

        bdd.passed.add(true);
      } catch (error) {
        bdd.passed.add(false);
      }
  }
}

/// Overrides `FlutterError.onError` defined by `TestWidgetsFlutterBinding._runTest()`,
/// so that overflow errors are only printed to the console, and not considered test failures.
///
/// This function should be called only by the `testWidgets()` body,
/// because only in this context `FlutterError.onError` is used to get exceptions.
///
/// It's not necessary to reset the default value of `FlutterError.onError`,
/// because the `TestWidgetsFlutterBinding.postTest()` method does that already.
///
/// See: https://stackoverflow.com/a/57501230/6696558
///
void _ignoreOverflowErrors() {
  //
  var handlerOriginal = FlutterError.onError;

  FlutterError.onError = (details) {
    var exception = details.exception;
    var ifOverflow = (exception is FlutterError) &&
        exception.diagnostics
            .map((diagnostic) => diagnostic.value)
            .whereType<List<Object>>()
            .expand((value) => value)
            .any((data) => data.toString().startsWith("A RenderFlex overflowed by"));

    if (ifOverflow)
      FlutterError.dumpErrorToConsole(details);
    else
      handlerOriginal!(details);
  };
}

/// During the binding process that happens inside the `testWidgets()` function,
/// the `BindingBase.initServiceExtensions()` method determines, based on the
/// operating system, the value of `debugDefaultTargetPlatformOverride`.
///
/// In common test situations, the operating system is Windows, causing
/// null to be assigned to `debugDefaultTargetPlatformOverride`.
///
/// Inside `testWidgets()`, right after executing the `WidgetTesterCallback`,
/// the `TestWidgetsFlutterBinding.runTest()` method calls the function
/// `debugAssertAllFoundationVarsUnset()` which requires that
/// `debugDefaultTargetPlatformOverride` is null, because it expects the test
/// to be run on Windows. As this is not the case, an error is thrown.
///
/// The easiest way to prevent this error from being thrown is by setting null
/// to the `debugDefaultTargetPlatformOverride` in the `WidgetTesterCallback` of the
/// `testWidgets()`.
///
/// Same explanation, slightly different:
/// https://stackoverflow.com/a/57628196/6696558
///
void _cleanTargetPlatformOverride() => (debugDefaultTargetPlatformOverride = null);

import 'dart:async';
import 'dart:core';
import 'dart:io';
import 'dart:math';

import 'package:characters/characters.dart';
import 'package:collection/collection.dart';
import "package:meta/meta.dart";
import 'package:test/test.dart';
import 'bdd_context.dart';
part 'bdd_runner.dart';

part 'bdd_feature.dart';
part 'bdd_background.dart';
part 'bdd_feature_description.dart';
part 'bdd_example.dart';
part 'bdd_scenario.dart';

/// This interface helps to format values in Examples and Tables.
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
  ]) : values = [
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
          v16
        ].nonNulls.toList();
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
      // 2) The `describe` method here is dynamic.
      return _value.describe().toString();
    } on NoSuchMethodError {
      // 3)
      return _value.toString();
    }
  }
}

class BddKeywords {
  //
  const BddKeywords({
    this.feature = 'Feature:',
    this.background = 'Background:',
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
    this.asA = 'As a',
    this.iWant = 'I want',
    this.soThat = 'So that',
  });

  const BddKeywords.only({
    this.feature = '',
    this.background = '',
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
    this.asA = '',
    this.iWant = '',
    this.soThat = '',
  });

  static const empty = const BddKeywords.only();

  final String feature,
      background,
      scenario,
      scenarioOutline,
      given,
      when,
      then,
      and,
      but,
      comment,
      examples,
      table,
      asA,
      iWant,
      soThat;
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
  ///   if (obj is User) return obj.userName;
  /// }
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

/// A marker mixin to indicate that a [_BaseTerm] can act as a trigger to run
/// the test.
///
/// Classes that mix in [BddRunnable] become valid targets for runner extensions
/// (e.g., `BddDartTestRunner`, `BddFlutterTestRunner`) to attach a `.run()`
/// method. Only terms that represent a valid end-of-chain position in the BDD
/// fluent API should mix in this mixin — for example, [BddThen], [BddExample],
/// and their corresponding code terms like [_ThenCode].
///
/// [BddScenario] intentionally does **not** mix in [BddRunnable], since a
/// scenario without steps is not a valid test.
mixin BddRunnable on _BaseTerm {}

/// A mixin that enables a [_BaseTerm] to have executable code blocks attached
/// to it via runner-specific extensions.
///
/// Runner extensions (e.g., `BddDartTestCodeable`) call [addCode] which creates
/// the corresponding internal code term and returns it. The type parameter [T]
/// represents the concrete code term type returned (e.g., `_GivenCode`), allowing
/// the runner extension to preserve the fluent chain's static type.
mixin BddCodeable<T> on _BaseTerm {
  /// Creates and registers the appropriate code term for this BDD step.
  ///
  /// Each mixing class implements this to return its corresponding code term.
  /// Use `.code()` from a runner import instead of calling this directly.
  @internal
  T addCode(CodeRun codeRun);
}

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

  String? _keywordPrefixVariation(BddConfig config) =>
      (variation == _Variation.and)
          ? config.keywordPrefix.and
          : (variation == _Variation.but)
              ? config.keywordPrefix.but
              : (variation == _Variation.note)
                  ? config.keywordPrefix.comment
                  : null;

  String? _keywordSuffixVariation(BddConfig config) =>
      (variation == _Variation.and)
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
  List<BddTableTerm> tables() =>
      // TODO: This was refactored, and BddExample is not of type BddTableTerm anymore.
      // TODO: Can remove the where.
      allTerms<BddTableTerm>().where((t) => t is! BddExample).toList();

  /// The example, if it exists, may have any number of rows.
  Set<val>? exampleRow(int? count) =>
      (count == null) ? null : example()?.rows[count];

  int numberOfExamples() {
    BddExample? _example = example();
    return (_example == null) ? 0 : _example.rows.length;
  }

  BddExample addExampleValues(List<val> values) {
    assert(values.isNotEmpty, 'Examples require at least one value.');
    final existing = example();
    if (existing != null) {
      return existing.appendExampleValues(values);
    }

    return BddExample(this, values);
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

  // TODO: MARCELO Remove?
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

  /// The high-level description of a test case in Gherkin. It describes a
  /// particular functionality or feature of the system being tested.
  BddScenario scenario(String text) => BddScenario(this, text);

  /// This keyword starts a step that sets up the initial context of the
  /// scenario. It's used to describe the state of the world before you begin
  /// the behavior you're specifying in this scenario. For example,
  /// "Given I am logged into the website" sets the scene for the actions that follow.
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

  String _featureSection(BddConfig config, bool withFeature) =>
      withFeature ? feature?.toString(config) ?? "" : "";

  String _backgroundSection(BddConfig config, bool withFeature) =>
      withFeature && feature?.backgroundFramework != null
          ? config.endOfLineChar + feature!.background.toString(config)
          : "";

  String _termsSection(BddConfig config) =>
      toMap(config).join(config.endOfLineChar) + config.endOfLineChar;

  @override
  String toString({
    BddConfig config = BddConfig._default,
    bool withFeature = false,
  }) =>
      _featureSection(config, withFeature) +
      _backgroundSection(config, withFeature) +
      _termsSection(config);
}

class BddGiven extends BddTerm with BddCodeable<_GivenCode>, BddRunnable {
  @override
  _GivenCode addCode(CodeRun codeRun) => _GivenCode(bdd, codeRun);

  BddGiven(BddFramework bdd, String text) : super(bdd, text, _Variation.term);

  BddGiven._(BddFramework bdd, String text, _Variation variation)
      : super(bdd, text, variation);

  BddGiven.note(BddFramework bdd, String text)
      : super(bdd, text, _Variation.note);

  @override
  String spaces(BddConfig config) => config.spaces + config.spaces;

  @override
  String keyword(BddConfig config) =>
      _keywordVariation(config) ?? config.keywords.given;

  @override
  String keywordPrefix(BddConfig config) =>
      _keywordPrefixVariation(config) ?? config.keywordPrefix.given;

  @override
  String keywordSuffix(BddConfig config) =>
      _keywordSuffixVariation(config) ?? config.keywordSuffix.given;

  @override
  String prefix(BddConfig config) =>
      _prefixVariation(config) ?? config.prefix.given;

  @override
  String suffix(BddConfig config) =>
      _suffixVariation(config) ?? config.suffix.given;

  /// A table must have a name and rows. The name is necessary if you want to
  /// read the values from it later (if not, just pass an empty string).
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
      BddGivenTable(bdd, tableName, row1, row2, row3, row4, row5, row6, row7,
          row8, row9, row10, row11, row12, row13, row14, row15, row16);

  /// This keyword is used to extend a 'Given', 'When', or 'Then' step.
  /// It allows you to add multiple conditions or actions in the same step
  /// without having to repeat the 'Given', 'When', or 'Then' keyword.
  /// For example, "And I should see a confirmation message" could follow
  /// a 'Then' step to further specify the expected outcomes.
  BddGiven and(String text) => BddGiven._(bdd, text, _Variation.and);

  /// This keyword is used similarly to "And," but it is typically used for
  /// negative conditions or to express a contrast with the previous step.
  /// It's a way to extend a "Given," "When," or "Then" step with an additional
  /// condition that contrasts with what was previously stated. For example,
  /// after a "Then" step, you might have "But I should not be logged out."
  /// This helps in creating more comprehensive scenarios by covering both
  /// what should happen and what should not happen under certain conditions.
  BddGiven but(String text) => BddGiven._(bdd, text, _Variation.but);

  /// Often used informally in comments within a Gherkin document to provide
  /// additional information, clarifications, or explanations about the scenario
  /// or steps. Comments in Gherkin are usually marked with a hashtag (#) and
  /// are ignored when the tests are executed. A "Note" can be useful for
  /// giving context or explaining the rationale behind a certain test scenario,
  /// making it easier for others to understand the purpose and scope of the test.
  BddGiven note(String text) => BddGiven._(bdd, text, _Variation.note);

  /// This keyword indicates the specific action taken by the user or the system.
  /// It's the trigger for the behavior that you're specifying. For instance,
  /// "When I click the 'Submit' button" describes the action taken after the
  /// initial context is set by the 'Given' step.
  BddWhen when(String text) => BddWhen(bdd, text);

  /// This keyword is used to describe the expected outcome or result after the
  /// 'When' step is executed. It's used to assert that a certain outcome should
  /// occur, which helps to validate whether the system behaves as expected.
  /// An example is, "Then I should be redirected to the dashboard".
  BddThen then(String text) => BddThen(bdd, text);

  @override
  // ignore: unnecessary_overrides
  String toString([BddConfig config = BddConfig._default]) =>
      super.toString(config);
}

class _GivenCode extends BddCodeTerm with BddCodeable<_GivenCode>, BddRunnable {
  _GivenCode(BddFramework bdd, CodeRun code) : super(bdd, code);

  @override
  _GivenCode addCode(CodeRun codeRun) => _GivenCode(bdd, codeRun);

  /// A table must have a name and rows. The name is necessary if you want to
  /// read the values from it later (if not, just pass an empty string).
  /// Example: `ctx.table('notifications').row(0).val('read') as bool`.
  BddGivenTable table(String tableName, row row1,
          [row? row2, row? row3, row? row4]) =>
      BddGivenTable(bdd, tableName, row1, row2, row3, row4);

  /// This keyword is used to extend a 'Given', 'When', or 'Then' step.
  /// It allows you to add multiple conditions or actions in the same step
  /// without having to repeat the 'Given', 'When', or 'Then' keyword.
  /// For example, "And I should see a confirmation message" could follow
  /// a 'Then' step to further specify the expected outcomes.
  BddGiven and(String text) => BddGiven._(bdd, text, _Variation.and);

  /// This keyword is used similarly to "And," but it is typically used for
  /// negative conditions or to express a contrast with the previous step.
  /// It's a way to extend a "Given," "When," or "Then" step with an additional
  /// condition that contrasts with what was previously stated. For example,
  /// after a "Then" step, you might have "But I should not be logged out."
  /// This helps in creating more comprehensive scenarios by covering both
  /// what should happen and what should not happen under certain conditions.
  BddGiven but(String text) => BddGiven._(bdd, text, _Variation.but);

  /// Often used informally in comments within a Gherkin document to provide
  /// additional information, clarifications, or explanations about the scenario
  /// or steps. Comments in Gherkin are usually marked with a hashtag (#) and
  /// are ignored when the tests are executed. A "Note" can be useful for
  /// giving context or explaining the rationale behind a certain test scenario,
  /// making it easier for others to understand the purpose and scope of the test.
  BddGiven note(String text) => BddGiven._(bdd, text, _Variation.note);

  /// This keyword indicates the specific action taken by the user or the system.
  /// It's the trigger for the behavior that you're specifying. For instance,
  /// "When I click the 'Submit' button" describes the action taken after the
  /// initial context is set by the 'Given' step.
  BddWhen when(String text) => BddWhen(bdd, text);

  /// This keyword is used to describe the expected outcome or result after the
  /// 'When' step is executed. It's used to assert that a certain outcome should
  /// occur, which helps to validate whether the system behaves as expected.
  /// An example is, "Then I should be redirected to the dashboard".
  BddThen then(String text) => BddThen(bdd, text);
}

class BddWhen extends BddTerm with BddCodeable<_WhenCode>, BddRunnable {
  @override
  _WhenCode addCode(CodeRun codeRun) => _WhenCode(bdd, codeRun);

  BddWhen(BddFramework bdd, String text) : super(bdd, text, _Variation.term);

  BddWhen._(BddFramework bdd, String text, _Variation variation)
      : super(bdd, text, variation);

  @override
  String spaces(BddConfig config) => config.spaces + config.spaces;

  @override
  String keyword(BddConfig config) =>
      _keywordVariation(config) ?? config.keywords.when;

  @override
  String keywordPrefix(BddConfig config) =>
      _keywordPrefixVariation(config) ?? config.keywordPrefix.when;

  @override
  String keywordSuffix(BddConfig config) =>
      _keywordSuffixVariation(config) ?? config.keywordSuffix.when;

  @override
  String prefix(BddConfig config) =>
      _prefixVariation(config) ?? config.prefix.when;

  @override
  String suffix(BddConfig config) =>
      _suffixVariation(config) ?? config.suffix.when;

  /// A table must have a name and rows. The name is necessary if you want to
  /// read the values from it later (if not, just pass an empty string).
  /// Example: `ctx.table('notifications').row(0).val('read') as bool`.
  BddWhenTable table(String tableName, row row1,
          [row? row2, row? row3, row? row4]) =>
      BddWhenTable(bdd, tableName, row1, row2, row3, row4);

  /// This keyword is used to extend a 'Given', 'When', or 'Then' step.
  /// It allows you to add multiple conditions or actions in the same step
  /// without having to repeat the 'Given', 'When', or 'Then' keyword.
  /// For example, "And I should see a confirmation message" could follow
  /// a 'Then' step to further specify the expected outcomes.
  BddWhen and(String text) => BddWhen._(bdd, text, _Variation.and);

  /// This keyword is used similarly to "And," but it is typically used for
  /// negative conditions or to express a contrast with the previous step.
  /// It's a way to extend a "Given," "When," or "Then" step with an additional
  /// condition that contrasts with what was previously stated. For example,
  /// after a "Then" step, you might have "But I should not be logged out."
  /// This helps in creating more comprehensive scenarios by covering both
  /// what should happen and what should not happen under certain conditions.
  BddWhen but(String text) => BddWhen._(bdd, text, _Variation.but);

  /// Often used informally in comments within a Gherkin document to provide
  /// additional information, clarifications, or explanations about the scenario
  /// or steps. Comments in Gherkin are usually marked with a hashtag (#) and
  /// are ignored when the tests are executed. A "Note" can be useful for
  /// giving context or explaining the rationale behind a certain test scenario,
  /// making it easier for others to understand the purpose and scope of the test.
  BddWhen note(String text) => BddWhen._(bdd, text, _Variation.note);

  /// This keyword is used to describe the expected outcome or result after the
  /// 'When' step is executed. It's used to assert that a certain outcome should
  /// occur, which helps to validate whether the system behaves as expected.
  /// An example is, "Then I should be redirected to the dashboard".
  BddThen then(String text) => BddThen(bdd, text);

  @override

  // ignore: unnecessary_overrides
  String toString([BddConfig config = BddConfig._default]) =>
      super.toString(config);
}

class _WhenCode extends BddCodeTerm with BddCodeable<_WhenCode>, BddRunnable {
  _WhenCode(BddFramework bdd, CodeRun code) : super(bdd, code);

  @override
  _WhenCode addCode(CodeRun codeRun) => _WhenCode(bdd, codeRun);

  /// A table must have a name and rows. The name is necessary if you want to
  /// read the values from it later (if not, just pass an empty string).
  /// Example: `ctx.table('notifications').row(0).val('read') as bool`.
  BddWhenTable table(String tableName, row row1,
          [row? row2, row? row3, row? row4]) =>
      BddWhenTable(bdd, tableName, row1, row2, row3, row4);

  /// This keyword is used to extend a 'Given', 'When', or 'Then' step.
  /// It allows you to add multiple conditions or actions in the same step
  /// without having to repeat the 'Given', 'When', or 'Then' keyword.
  /// For example, "And I should see a confirmation message" could follow
  /// a 'Then' step to further specify the expected outcomes.
  BddWhen and(String text) => BddWhen._(bdd, text, _Variation.and);

  /// This keyword is used similarly to "And," but it is typically used for
  /// negative conditions or to express a contrast with the previous step.
  /// It's a way to extend a "Given," "When," or "Then" step with an additional
  /// condition that contrasts with what was previously stated. For example,
  /// after a "Then" step, you might have "But I should not be logged out."
  /// This helps in creating more comprehensive scenarios by covering both
  /// what should happen and what should not happen under certain conditions.
  BddWhen but(String text) => BddWhen._(bdd, text, _Variation.but);

  /// Often used informally in comments within a Gherkin document to provide
  /// additional information, clarifications, or explanations about the scenario
  /// or steps. Comments in Gherkin are usually marked with a hashtag (#) and
  /// are ignored when the tests are executed. A "Note" can be useful for
  /// giving context or explaining the rationale behind a certain test scenario,
  /// making it easier for others to understand the purpose and scope of the test.
  BddWhen note(String text) => BddWhen._(bdd, text, _Variation.note);

  /// This keyword is used to describe the expected outcome or result after the
  BddThen then(String text) => BddThen(bdd, text);
}

class BddThen extends BddTerm
    with BddCodeable<_ThenCode>, BddRunnable, BddExampleAttachable {
  @override
  _ThenCode addCode(CodeRun codeRun) => _ThenCode(bdd, codeRun);

  BddThen(BddFramework bdd, String text) : super(bdd, text, _Variation.term);

  BddThen._(BddFramework bdd, String text, _Variation variation)
      : super(bdd, text, variation);

  @override
  String spaces(BddConfig config) => config.spaces + config.spaces;

  @override
  String keyword(BddConfig config) =>
      _keywordVariation(config) ?? config.keywords.then;

  @override
  String keywordPrefix(BddConfig config) =>
      _keywordPrefixVariation(config) ?? config.keywordPrefix.then;

  @override
  String keywordSuffix(BddConfig config) =>
      _keywordSuffixVariation(config) ?? config.keywordSuffix.then;

  @override
  String prefix(BddConfig config) =>
      _prefixVariation(config) ?? config.prefix.then;

  @override
  String suffix(BddConfig config) =>
      _suffixVariation(config) ?? config.suffix.then;

  /// A table must have a name and rows. The name is necessary if you want to
  /// read the values from it later (if not, just pass an empty string).
  /// Example: `ctx.table('notifications').row(0).val('read') as bool`.
  BddThenTable table(String tableName, row row1,
          [row? row2, row? row3, row? row4]) =>
      BddThenTable(bdd, tableName, row1, row2, row3, row4);

  /// This keyword is used to extend a 'Given', 'When', or 'Then' step.
  /// It allows you to add multiple conditions or actions in the same step
  /// without having to repeat the 'Given', 'When', or 'Then' keyword.
  /// For example, "And I should see a confirmation message" could follow
  /// a 'Then' step to further specify the expected outcomes.
  BddThen and(String text) => BddThen._(bdd, text, _Variation.and);

  /// This keyword is used similarly to "And," but it is typically used for
  /// negative conditions or to express a contrast with the previous step.
  /// It's a way to extend a "Given," "When," or "Then" step with an additional
  /// condition that contrasts with what was previously stated. For example,
  /// after a "Then" step, you might have "But I should not be logged out."
  /// This helps in creating more comprehensive scenarios by covering both
  /// what should happen and what should not happen under certain conditions.
  BddThen but(String text) => BddThen._(bdd, text, _Variation.but);

  /// Often used informally in comments within a Gherkin document to provide
  /// additional information, clarifications, or explanations about the scenario
  /// or steps. Comments in Gherkin are usually marked with a hashtag (#) and
  /// are ignored when the tests are executed. A "Note" can be useful for
  /// giving context or explaining the rationale behind a certain test scenario,
  /// making it easier for others to understand the purpose and scope of the test.
  BddThen note(String text) => BddThen._(bdd, text, _Variation.note);

  @visibleForTesting
  BddFramework testRun(CodeRun code, BddReporter reporter) {
    _TestRun(code, reporter).run(bdd);
    return bdd;
  }

  @override
  // ignore: unnecessary_overrides
  String toString([BddConfig config = BddConfig._default]) =>
      super.toString(config);
}

class _ThenCode extends BddCodeTerm
    with BddCodeable<_ThenCode>, BddRunnable, BddExampleAttachable {
  _ThenCode(BddFramework bdd, CodeRun code) : super(bdd, code);

  @override
  _ThenCode addCode(CodeRun codeRun) => _ThenCode(bdd, codeRun);

  /// A table must have a name and rows. The name is necessary if you want to
  /// read the values from it later (if not, just pass an empty string).
  /// Example: `ctx.table('notifications').row(0).val('read') as bool`.
  BddThenTable table(String tableName, row row1,
          [row? row2, row? row3, row? row4]) =>
      BddThenTable(bdd, tableName, row1, row2, row3, row4);

  /// This keyword is used to extend a 'Given', 'When', or 'Then' step.
  /// It allows you to add multiple conditions or actions in the same step
  /// without having to repeat the 'Given', 'When', or 'Then' keyword.
  /// For example, "And I should see a confirmation message" could follow
  /// a 'Then' step to further specify the expected outcomes.
  BddThen and(String text) => BddThen._(bdd, text, _Variation.and);

  /// This keyword is used similarly to "And," but it is typically used for
  /// negative conditions or to express a contrast with the previous step.
  /// It's a way to extend a "Given," "When," or "Then" step with an additional
  /// condition that contrasts with what was previously stated. For example,
  /// after a "Then" step, you might have "But I should not be logged out."
  /// This helps in creating more comprehensive scenarios by covering both
  /// what should happen and what should not happen under certain conditions.
  BddThen but(String text) => BddThen._(bdd, text, _Variation.but);

  /// Often used informally in comments within a Gherkin document to provide
  /// additional information, clarifications, or explanations about the scenario
  /// or steps. Comments in Gherkin are usually marked with a hashtag (#) and
  /// are ignored when the tests are executed. A "Note" can be useful for
  /// giving context or explaining the rationale behind a certain test scenario,
  /// making it easier for others to understand the purpose and scope of the test.
  BddThen note(String text) => BddThen._(bdd, text, _Variation.note);

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

  BddTableTerm(BddFramework bdd, this.tableName)
      : super(bdd, '', _Variation.term);

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

class BddGivenTable extends BddTableTerm with BddCodeable<_GivenCode> {
  @override
  _GivenCode addCode(CodeRun codeRun) => _GivenCode(bdd, codeRun);

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
    ].nonNulls);
  }

  /// This keyword is used to extend a 'Given', 'When', or 'Then' step.
  /// It allows you to add multiple conditions or actions in the same step
  /// without having to repeat the 'Given', 'When', or 'Then' keyword.
  /// For example, "And I should see a confirmation message" could follow
  /// a 'Then' step to further specify the expected outcomes.
  BddGiven and(String text) => BddGiven._(bdd, text, _Variation.and);

  /// This keyword is used similarly to "And," but it is typically used for
  /// negative conditions or to express a contrast with the previous step.
  /// It's a way to extend a "Given," "When," or "Then" step with an additional
  /// condition that contrasts with what was previously stated. For example,
  /// after a "Then" step, you might have "But I should not be logged out."
  /// This helps in creating more comprehensive scenarios by covering both
  /// what should happen and what should not happen under certain conditions.
  BddGiven but(String text) => BddGiven._(bdd, text, _Variation.but);

  /// Often used informally in comments within a Gherkin document to provide
  /// additional information, clarifications, or explanations about the scenario
  /// or steps. Comments in Gherkin are usually marked with a hashtag (#) and
  /// are ignored when the tests are executed. A "Note" can be useful for
  /// giving context or explaining the rationale behind a certain test scenario,
  /// making it easier for others to understand the purpose and scope of the test.
  BddGiven note(String text) => BddGiven._(bdd, text, _Variation.note);

  /// This keyword indicates the specific action taken by the user or the system.
  /// It's the trigger for the behavior that you're specifying. For instance,
  /// "When I click the 'Submit' button" describes the action taken after the
  /// initial context is set by the 'Given' step.
  BddWhen when(String text) => BddWhen(bdd, text);

  @override
  // ignore: unnecessary_overrides
  String toString([BddConfig config = BddConfig._default]) =>
      super.toString(config);
}

class BddWhenTable extends BddTableTerm
    with BddCodeable<_WhenCode>, BddRunnable {
  @override
  _WhenCode addCode(CodeRun codeRun) => _WhenCode(bdd, codeRun);

  //
  BddWhenTable(BddFramework bdd, String tableName, row row1,
      [row? row2, row? row3, row? row4])
      : super(bdd, tableName) {
    rows.addAll([row1, row2, row3, row4].nonNulls);
  }

  /// This keyword is used to extend a 'Given', 'When', or 'Then' step.
  /// It allows you to add multiple conditions or actions in the same step
  /// without having to repeat the 'Given', 'When', or 'Then' keyword.
  /// For example, "And I should see a confirmation message" could follow
  /// a 'Then' step to further specify the expected outcomes.
  BddWhen and(String text) => BddWhen._(bdd, text, _Variation.and);

  /// This keyword is used similarly to "And," but it is typically used for
  /// negative conditions or to express a contrast with the previous step.
  /// It's a way to extend a "Given," "When," or "Then" step with an additional
  /// condition that contrasts with what was previously stated. For example,
  /// after a "Then" step, you might have "But I should not be logged out."
  /// This helps in creating more comprehensive scenarios by covering both
  /// what should happen and what should not happen under certain conditions.
  BddWhen but(String text) => BddWhen._(bdd, text, _Variation.but);

  /// Often used informally in comments within a Gherkin document to provide
  /// additional information, clarifications, or explanations about the scenario
  /// or steps. Comments in Gherkin are usually marked with a hashtag (#) and
  /// are ignored when the tests are executed. A "Note" can be useful for
  /// giving context or explaining the rationale behind a certain test scenario,
  /// making it easier for others to understand the purpose and scope of the test.
  BddWhen note(String text) => BddWhen._(bdd, text, _Variation.note);

  /// This keyword is used to describe the expected outcome or result after the
  /// 'When' step is executed. It's used to assert that a certain outcome should
  /// occur, which helps to validate whether the system behaves as expected.
  /// An example is, "Then I should be redirected to the dashboard".
  BddThen then(String text) => BddThen(bdd, text);

  @override
  // ignore: unnecessary_overrides
  String toString([BddConfig config = BddConfig._default]) =>
      super.toString(config);
}

class BddThenTable extends BddTableTerm
    with BddCodeable<_ThenCode>, BddRunnable, BddExampleAttachable {
  @override
  _ThenCode addCode(CodeRun codeRun) => _ThenCode(bdd, codeRun);

  //
  BddThenTable(BddFramework bdd, String tableName, row row1,
      [row? row2, row? row3, row? row4])
      : super(bdd, tableName) {
    rows.addAll([row1, row2, row3, row4].nonNulls);
  }

  /// This keyword is used to extend a 'Given', 'When', or 'Then' step.
  /// It allows you to add multiple conditions or actions in the same step
  /// without having to repeat the 'Given', 'When', or 'Then' keyword.
  /// For example, "And I should see a confirmation message" could follow
  /// a 'Then' step to further specify the expected outcomes.
  BddThen and(String text) => BddThen._(bdd, text, _Variation.and);

  /// This keyword is used similarly to "And," but it is typically used for
  /// negative conditions or to express a contrast with the previous step.
  /// It's a way to extend a "Given," "When," or "Then" step with an additional
  /// condition that contrasts with what was previously stated. For example,
  /// after a "Then" step, you might have "But I should not be logged out."
  /// This helps in creating more comprehensive scenarios by covering both
  /// what should happen and what should not happen under certain conditions.
  BddThen but(String text) => BddThen._(bdd, text, _Variation.but);

  /// Often used informally in comments within a Gherkin document to provide
  /// additional information, clarifications, or explanations about the scenario
  /// or steps. Comments in Gherkin are usually marked with a hashtag (#) and
  /// are ignored when the tests are executed. A "Note" can be useful for
  /// giving context or explaining the rationale behind a certain test scenario,
  /// making it easier for others to understand the purpose and scope of the test.
  BddThen note(String text) => BddThen._(bdd, text, _Variation.note);

  @override
  // ignore: unnecessary_overrides
  String toString([BddConfig config = BddConfig._default]) =>
      super.toString(config);

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

  List<String> toMap([BddConfig config = BddConfig._default]) =>
      _bdd.toMap(config);

  @override
  String toString([BddConfig config = BddConfig._default]) =>
      _bdd.toString(config: config);

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
      ..addAll([r1, r2, r3, r4, r5].nonNulls);
  }

  static Future<void> reportAll() async {
    tearDownAll(() async {
      stdout.writeln(yellow);
      stdout.writeln('RESULTS ══════════════════════════════════════════════');
      stdout.writeln(
          'TOTAL: ${runInfo.totalTestCount} tests (${runInfo.testCount} BDDs)');
      stdout.writeln('PASSED: ${runInfo.passedCount} tests');
      stdout.writeln('FAILED: ${runInfo.failedCount} tests');
      stdout.writeln('SKIPPED: ${runInfo.skipCount} tests');
      stdout.writeln(
          '══════════════════════════════════════════════════════$reset');
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
    BddFeature? feature =
        features.firstWhereOrNull((feature) => feature.title == _feature.title);

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
          onMatch: (m) => m[0] == ' ' ? '_' : '',
          onNonMatch: (m) => m.toLowerCase());
}

class TestRunConfig {
  final String? testOn;
  final Timeout? timeout;
  final dynamic tags;
  final Map<String, dynamic>? onPlatform;
  final int? retry;

  TestRunConfig(
      {this.testOn, this.timeout, this.tags, this.onPlatform, this.retry});
}

class _RunInfo {
  int totalTestCount = 0;
  int testCount = 0;
  int skipCount = 0;
  int passedCount = 0;
  int failedCount = 0;

  bool overflowIsSetUp = false;
}

typedef CodeRun = FutureOr<void> Function(BddContext ctx);

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
        final background = bdd.feature?.backgroundFramework;
        if (background != null) {
          for (CodeRun codeRun in background.codeTerms
              .map((BddCodeTerm codeTerm) => codeTerm.codeRun)) {
            codeRun.call(ctx);
          }
        }

        /// Run all bdd code.
        Iterable<CodeRun> codeRuns =
            bdd.codeTerms.map((BddCodeTerm codeTerm) => codeTerm.codeRun);
        for (CodeRun codeRun in codeRuns) {
          codeRun.call(ctx);
        }

        bdd.passed.add(true);
      } catch (error) {
        bdd.passed.add(false);
      }
  }
}

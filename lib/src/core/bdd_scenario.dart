part of 'bdd_base.dart';

/// Represents a Gherkin Scenario.
///
/// A [BddScenario] is a single test case within a [BddFeature]. It contains a
/// description and a series of steps (Given, When, Then, And, But) that define
/// the behavior being tested.
///
/// If the scenario contains an [BddExample], it will be rendered as a
/// "Scenario Outline" in Gherkin format, allowing parameterization of steps.
class BddScenario extends BddTerm {
  /// Creates a new [BddScenario] with the given [text] description.
  ///
  /// The [text] should concisely describe the scenario being tested.
  BddScenario(BddFramework bdd, String text)
      : super(bdd, text, _Variation.term);

  /// Returns true if this scenario contains examples (tables).
  ///
  /// When examples are present, the scenario is rendered as a "Scenario Outline"
  /// in Gherkin format.
  bool get containsExample => bdd.terms.any((term) => term is BddExample);

  @override
  /// Returns the indentation string for this term based on [BddConfig].
  String spaces(BddConfig config) => config.spaces;

  @override
  /// Returns the keyword for this scenario: "Scenario:" or "Scenario Outline:"
  /// when examples are present.
  String keyword(BddConfig config) => containsExample //
      ? config.keywords.scenarioOutline
      : config.keywords.scenario;

  @override
  /// Returns the keyword prefix configuration.
  String keywordPrefix(BddConfig config) => containsExample //
      ? config.keywordPrefix.scenarioOutline
      : config.keywordPrefix.scenario;

  @override
  /// Returns the keyword suffix configuration.
  String keywordSuffix(BddConfig config) => containsExample //
      ? config.keywordSuffix.scenarioOutline
      : config.keywordSuffix.scenario;

  @override
  /// Returns the prefix for the scenario text.
  String prefix(BddConfig config) => containsExample //
      ? config.prefix.scenarioOutline
      : config.prefix.scenario;

  @override
  /// Returns the suffix for the scenario text.
  String suffix(BddConfig config) => containsExample //
      ? config.suffix.scenarioOutline
      : config.suffix.scenario;

  /// Creates a Given step that sets up the initial context of the scenario.
  ///
  /// The Given step describes the state of the world before the behavior being
  /// specified begins. It's used to establish preconditions and initial state.
  ///
  /// Example:
  /// ```dart
  /// Bdd(feature)
  ///   .scenario('user logs in')
  ///   .given('I am on the login page');
  /// ```
  BddGiven given(String text) => BddGiven(bdd, text);

  /// Creates a Note step for adding comments to the scenario.
  ///
  /// Often used informally in comments within a Gherkin document to provide
  /// additional information. Comments in Gherkin are ignored when tests execute.
  ///
  /// Example:
  /// ```dart
  /// Bdd(feature)
  ///   .scenario('user logs in')
  ///   .note('This test covers the main success path');
  /// ```
  BddGiven note(String text) => BddGiven._(bdd, text, _Variation.note);

  /// Creates a When step that describes the action or event.
  ///
  /// The When step indicates the specific action taken by the user or the system.
  /// It's the trigger for the behavior being specified.
  ///
  /// This allows scenarios to start directly with When without requiring Given first.
  ///
  /// Example:
  /// ```dart
  /// Bdd(feature)
  ///   .scenario('calculate sum')
  ///   .when('I add 2 and 3');
  /// ```
  BddWhen when(String text) => BddWhen(bdd, text);

  /// Creates a Then step that describes the expected outcome or result.
  ///
  /// The Then step is used to assert that a certain outcome should occur after
  /// the When step is executed. It helps validate whether the system behaves
  /// as expected.
  ///
  /// This allows scenarios to start directly with Then without requiring Given
  /// or When first.
  ///
  /// Example:
  /// ```dart
  /// Bdd(feature)
  ///   .scenario('calculate sum')
  ///   .then('the result should be 5');
  /// ```
  BddThen then(String text) => BddThen(bdd, text);

  @override
  /// Returns the Gherkin string representation of this scenario.
  // ignore: unnecessary_overrides
  String toString([BddConfig config = BddConfig._default]) =>
      super.toString(config);
}
part of 'bdd_base.dart';

/// Represents a Gherkin Feature.
///
/// A [BddFeature] is the highest-level organization in BDD. It contains a title,
/// an optional description, and a set of BDD scenarios (represented by [BddFramework]).
///
/// You can also define a [background] for the feature, which provides common steps
/// that run before every scenario.
class BddFeature {
  /// The title of the feature.
  final String title;

  /// An optional structured description (plain text or User Story).
  final FeatureDescription? _description;

  /// Returns the plain text description, if any.
  String? get description => _description?.text;

  /// Internal list of scenarios belonging to this feature.
  final List<BddFramework> _bdds;

  /// Internal storage for the background object.
  BddFramework? _background;

  /// Provides access to the [BddBackground] for this feature.
  ///
  /// The background allows you to add context and common setup steps to the scenarios.
  /// Steps defined here will execute before each scenario's own steps.
  BddBackground get background {
    _background ??= BddFramework(this);
    return BddBackground(BddFramework(this), _background!);
  }

  /// Internal access for engines (e.g. BddEngine) to retrieve the background setup steps.
  BddFramework? get backgroundFramework => _background;

  /// Returns a copy of the list of scenarios ([BddFramework] instances) in this feature.
  List<BddFramework> get bdds => _bdds.toList();

  /// Returns true if the feature title is empty.
  bool get isEmpty => title.isEmpty;

  /// Returns true if the feature has a non-empty title.
  bool get isNotEmpty => title.isNotEmpty;

  /// Creates a new [BddFeature] with the given [title] and optional [description].
  BddFeature(this.title, {String? description})
      : _description =
            description != null ? FeatureDescription(text: description) : null,
        _bdds = [];

  /// Creates a new [BddFeature] with a structured User Story description.
  ///
  /// Example:
  /// ```dart
  /// var feature = BddFeature.userStory(
  ///   'User Login',
  ///   asA: 'Registered User',
  ///   iWant: 'to log into my account',
  ///   soThat: 'I can access my private dashboard',
  /// );
  /// ```
  BddFeature.userStory(
    this.title, {
    required String asA,
    required String iWant,
    required String soThat,
  })  : _description = FeatureDescription.userStory(
          asA: asA,
          iWant: iWant,
          soThat: soThat,
        ),
        _bdds = [];

  /// Returns a list of [TestResult] objects for all scenarios in this feature.
  List<TestResult> get testResults =>
      _bdds.map((bdd) => TestResult(bdd)).toList();

  /// An internal list used for tracking results during execution.
  List<BddFramework> result = [];

  /// Adds a scenario ([BddFramework]) to this feature.
  ///
  /// This method ensures that the same scenario instance is not added multiple times.
  void add(BddFramework bdd) {
    if (!_bdds.contains(bdd)) {
      _bdds.add(bdd);
    }
  }

  /// Returns the Gherkin string representation of this feature.
  ///
  /// Includes the feature keyword, title, and description if defined.
  @override
  String toString([BddConfig config = BddConfig._default]) {
    var result = config.keywordPrefix.feature +
        config.keywords.feature +
        config.keywordSuffix.feature +
        ' ' +
        config.prefix.feature +
        _singleLine(title) +
        config.suffix.feature +
        config.endOfLineChar;

    if (_description != null) {
      result += _description.format(config);
    }

    return result;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BddFeature &&
          runtimeType == other.runtimeType &&
          title == other.title;

  @override
  int get hashCode => title.hashCode;
}

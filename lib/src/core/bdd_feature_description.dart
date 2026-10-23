part of 'bdd_base.dart';

/// Represents the description of a BDD feature.
/// It can be either a plain text description or a structured User Story.
class FeatureDescription {
  /// The plain text description, if any.
  final String? text;

  /// The 'As a' part of the User Story.
  final String? asA;

  /// The 'I want' part of the User Story.
  final String? iWant;

  /// The 'So that' part of the User Story.
  final String? soThat;

  /// Creates a plain text feature description.
  FeatureDescription({this.text})
      : asA = null,
        iWant = null,
        soThat = null;

  /// Creates a structured User Story feature description.
  FeatureDescription.userStory({
    required this.asA,
    required this.iWant,
    required this.soThat,
  }) : text = null;

  /// Formats the description according to the provided [config].
  String format(BddConfig config) {
    if (text != null) {
      var parts = text!.trim().split('\n');
      return config.spaces +
          config.prefix.feature +
          parts.join(config.endOfLineChar + config.spaces) +
          config.suffix.feature +
          config.endOfLineChar;
    } else {
      String result = "";
      result += config.spaces +
          config.keywords.asA +
          ' ' +
          _singleLine(asA!) +
          config.endOfLineChar;
      result += config.spaces +
          config.keywords.iWant +
          ' ' +
          _singleLine(iWant!) +
          config.endOfLineChar;
      result += config.spaces +
          config.keywords.soThat +
          ' ' +
          _singleLine(soThat!) +
          config.endOfLineChar;
      return result;
    }
  }
}

import 'package:bdd_framework/bdd_framework.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BddScenario', () {
    test('should support full Given-When-Then chain', () {
      final feature = BddFeature('Test');
      final bdd = Bdd(feature)
          .scenario('Test')
          .given('condition')
          .when('action')
          .then('result');

      expect(bdd.toString(), isNotEmpty);
    });

    test('should allow starting with when directly', () {
      final feature = BddFeature('Test');
      final bdd = Bdd(feature)
          .scenario('Test')
          .when('action')
          .then('result');

      expect(bdd.toString(), isNotEmpty);
    });

    test('should allow starting with then directly', () {
      final feature = BddFeature('Test');
      final bdd = Bdd(feature)
          .scenario('Test')
          .then('result');

      expect(bdd.toString(), isNotEmpty);
    });

    test('should support then followed by and', () {
      final feature = BddFeature('Test');
      final bdd = Bdd(feature)
          .scenario('Test')
          .then('result')
          .and('more');

      expect(bdd.toString(), isNotEmpty);
    });

    test('should work with runner config', () {
      final feature = BddFeature('Test');
      final bdd = Bdd(feature)
          .scenario('Test')
          .when('action');

      expect(bdd.toString(BddRunner.config), isNotEmpty);
    });

    test('should work with default config', () {
      final feature = BddFeature('Test');
      final bdd = Bdd(feature)
          .scenario('Test')
          .given('condition')
          .when('action')
          .then('result');

      expect(bdd.toString(BddConfig()), isNotEmpty);
    });
  });
}
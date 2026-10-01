import 'package:bdd_framework/bdd_framework.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BddFeature', () {
    group('Basic Properties', () {
      test('should construct with a title successfully', () {
        final feature = BddFeature('Login System');
        expect(feature.title, 'Login System');
        expect(feature.description, isNull);
        expect(feature.backgroundFramework, isNull);
        expect(feature.bdds, isEmpty);
        expect(feature.isNotEmpty, isTrue);
        expect(feature.isEmpty, isFalse);
      });

      test('should handle an empty title', () {
        final feature = BddFeature('');
        expect(feature.isEmpty, isTrue);
        expect(feature.isNotEmpty, isFalse);
      });

      test('should consider equality based exclusively on identical title', () {
        final featureA = BddFeature('Payment Gateway');
        final featureB =
            BddFeature('Payment Gateway', description: 'Testing out payments');
        final featureC = BddFeature('User Profiles');

        expect(featureA, equals(featureB));
        expect(featureA, isNot(equals(featureC)));
        expect(featureA.hashCode, equals(featureB.hashCode));
      });
    });

    group('toString()', () {
      test('should render correctly with default config', () {
        final feature = BddFeature('Login System');
        final output = feature.toString(const BddConfig());
        expect(output, 'Feature: Login System\n');
      });

      test('should apply bold/italic markers when using BddRunner config', () {
        final feature = BddFeature('Login System');
        final output = feature.toString(BddRunner.config);
        const bi = BddRunner.boldItalic;
        const bo = BddRunner.boldItalicOff;
        expect(output, '${bi}Feature:$bo Login System\n');
      });
    });
  });
}
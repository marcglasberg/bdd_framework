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

    group('collections', () {
      test('adds scenarios once and returns a defensive collection copy', () {
        final feature = BddFeature('Checkout');
        final bdd = Bdd(feature).scenario('payment').then('paid').bdd;
        feature.add(bdd);
        feature.add(bdd);
        expect(feature.bdds, [bdd]);
        feature.bdds.clear();
        expect(feature.bdds, [bdd]);
      });

      test('testResults maps every scenario and its live result state', () {
        final feature = BddFeature('Dashboard');
        final first = Bdd(feature).scenario('graph').when('load').bdd;
        final second = Bdd(feature).scenario('stats').then('visible').bdd;
        feature.add(first);
        feature.add(second);
        first.passed.add(true);
        second.passed.add(false);
        expect(feature.testResults, hasLength(2));
        expect(feature.testResults.first.passed, [true]);
        expect(feature.testResults.last.passed, [false]);
        expect(feature.testResults.first.terms, first.textTerms);
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

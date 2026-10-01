import 'package:bdd_framework/bdd_framework.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BddFeature', () {
    group('toString()', () {
      group('without description', () {
        test('should render only the Feature keyword', () {
          final feature = BddFeature('Login System');
          final output = feature.toString(const BddConfig());
          expect(output, 'Feature: Login System\n');
        });
      });

      group('with single-line description', () {
        test('should include the description on the second line', () {
          final feature = BddFeature('Login System',
              description: 'Ensures users can authenticate');
          final output = feature.toString(const BddConfig());
          expect(output, 'Feature: Login System\n  Ensures users can authenticate\n');
        });
      });

      group('with multi-line description', () {
        test('should preserve each line with proper indentation', () {
          final feature = BddFeature(
            'Login System',
            description:
                'Ensures users can authenticate\nProvides OTP functionality\nProtects against CSRF',
          );
          final output = feature.toString(const BddConfig());
          expect(
            output,
            [
              'Feature: Login System',
              '  Ensures users can authenticate',
              '  Provides OTP functionality',
              '  Protects against CSRF',
              '',
            ].join('\n'),
          );
        });
      });

      group('with Background', () {
        test('should exclude Background from toString output', () {
          final feature = BddFeature('Payment Checkout');
          feature.background.given('a valid credit card is stored');

          final output = feature.toString(const BddConfig());
          expect(output, 'Feature: Payment Checkout\n');

          final bgOutput = feature.background.toString(const BddConfig());
          expect(
            bgOutput,
            [
              '  Background:',
              '    Given a valid credit card is stored',
              '',
            ].join('\n'),
          );
        });
      });
    });

    group('userStory()', () {
      group('with User Story parts', () {
        test('should set the title and isNotEmpty flag correctly', () {
          final feature = BddFeature.userStory(
            'User Login',
            asA: 'Registered User',
            iWant: 'to log into my account',
            soThat: 'I can access my private dashboard',
          );
          expect(feature.title, 'User Login');
          expect(feature.description, isNull);
          expect(feature.isNotEmpty, isTrue);
        });

        test('should render the standard user story format by default', () {
          final feature = BddFeature.userStory(
            'User Login',
            asA: 'Registered User',
            iWant: 'to log into my account',
            soThat: 'I can access my private dashboard',
          );
          final output = feature.toString(const BddConfig());
          expect(
            output,
            [
              'Feature: User Login',
              '  As a Registered User',
              '  I want to log into my account',
              '  So that I can access my private dashboard',
              '',
            ].join('\n'),
          );
        });

        test('should consider equality based on title only', () {
          final featureA = BddFeature.userStory(
            'Payment Gateway',
            asA: 'Customer',
            iWant: 'to pay',
            soThat: 'I can complete checkout',
          );
          final featureB = BddFeature('Payment Gateway');

          expect(featureA, equals(featureB));
          expect(featureA.hashCode, equals(featureB.hashCode));
        });

        test('should exclude Background from userStory toString output', () {
          final feature = BddFeature.userStory(
            'Payment Checkout',
            asA: 'Customer',
            iWant: 'to checkout my cart',
            soThat: 'I can receive my order',
          );
          feature.background.given('a valid credit card is stored');

          final output = feature.toString(const BddConfig());
          expect(
            output,
            [
              'Feature: Payment Checkout',
              '  As a Customer',
              '  I want to checkout my cart',
              '  So that I can receive my order',
              '',
            ].join('\n'),
          );
        });
      });

      group('toString() with User Story', () {
        test('should apply bold/italic markers when using BddRunner config', () {
          final feature = BddFeature.userStory(
            'User Login',
            asA: 'Registered User',
            iWant: 'to log into my account',
            soThat: 'I can access my private dashboard',
          );
          final output = feature.toString(BddRunner.config);
          const bi = BddRunner.boldItalic;
          const bo = BddRunner.boldItalicOff;
          expect(
            output,
            [
              '${bi}Feature:$bo User Login',
              '  As a Registered User',
              '  I want to log into my account',
              '  So that I can access my private dashboard',
              '',
            ].join('\n'),
          );
        });
      });
    });
  });
}
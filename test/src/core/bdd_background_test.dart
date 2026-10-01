import 'package:bdd_framework/bdd_framework.dart';
import 'package:bdd_framework/flutter_test.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BddBackground', () {
    group('toString()', () {
      group('without steps', () {
        test('should render only the Background keyword', () {
          final feature = BddFeature('Feature Without Steps');
          final background = feature.background;
          final output = background.toString(const BddConfig());
          expect(output, '  Background:\n');
        });
      });

      group('with single step', () {
        test('should render keyword and step correctly', () {
          final feature = BddFeature('Feature With Single Step');
          final background = feature.background;
          background.given('a condition');

          final output = background.toString(const BddConfig());
          expect(output, '  Background:\n    Given a condition\n');
        });
      });

      group('with multiple steps', () {
        test('should maintain order and newlines correctly', () {
          final feature = BddFeature('Feature With Multiple Steps');
          final background = feature.background;
          background.given('first step').and('second step').note('a comment');

          final output = background.toString(const BddConfig());
          expect(
            output,
            [
              '  Background:',
              '    Given first step',
              '    And second step',
              '    # A comment',
              '',
            ].join('\n'),
          );
        });
      });

      group('with custom keywords', () {
        test('should respect the custom keywords', () {
          final feature = BddFeature('Custom Keyword Feature');
          final background = feature.background;
          background.given('initial state');

          const customConfig = BddConfig(
            keywords: BddKeywords(
              background: 'Context:',
              given: 'Assume',
            ),
          );

          final output = background.toString(customConfig);
          expect(output, '  Context:\n    Assume initial state\n');
        });
      });

      group('with custom indentation', () {
        test('should return correct indentation based on config', () {
          final feature = BddFeature('Indentation Feature');
          final background = feature.background;
          background.given('a condition');

          const customConfig = BddConfig(
            padChar: '\t',
            indent: 1,
          );

          final output = background.toString(customConfig);
          expect(output, '\tBackground:\n\t\tGiven a condition\n');
        });
      });
    });

    group('Step Delegation', () {
      test('should register step in internal framework when given is called', () {
        final feature = BddFeature('Delegation Feature');
        final background = feature.background;

        background.given('state setup');

        final internalFramework = feature.backgroundFramework!;
        expect(internalFramework.terms.length, 1);
        final term = internalFramework.terms.first;
        expect(term, isA<BddGiven>());
        expect((term as BddGiven).text, 'state setup');
      });

      test('should create BddGiven note instance when note is called', () {
        final feature = BddFeature('Delegation Feature');
        final background = feature.background;

        background.note('important context');

        final internalFramework = feature.backgroundFramework!;
        expect(internalFramework.terms.length, 1);
        final term = internalFramework.terms.first;
        expect(term, isA<BddGiven>());
        expect((term as BddGiven).text, 'important context');
        expect(term.toString(const BddConfig()), '    # Important context');
      });

      test('should include delegated steps in final toString output', () {
        final feature = BddFeature('Delegation Feature');
        feature.background.given('step 1');
        feature.background.given('step 2');

        final output = feature.background.toString(const BddConfig());
        expect(output, contains('Given step 1'));
        expect(output, contains('Given step 2'));
      });
    });

    group('Inheritance & Structure', () {
      test('should pass empty text to super class constructor', () {
        final feature = BddFeature('Structure Feature');
        final background = feature.background;
        expect(background.text, isEmpty);
      });

      test('should return empty strings for prefix and suffix', () {
        final feature = BddFeature('Structure Feature');
        final background = feature.background;
        const config = BddConfig();

        expect(background.prefix(config), isEmpty);
        expect(background.suffix(config), isEmpty);
      });
    });

    group('toString()', () {
      test('should render feature, background and scenario with default config', () {
        final feature = BddFeature('Background Feature');
        feature.background.given('shared setup');

        final BddFramework bdd = Bdd(feature);
        bdd
            .scenario('Flow')
            .given('initial condition')
            .when('action occurs')
            .then('outcome happens');

        final output = bdd.toString(
          config: const BddConfig(),
          withFeature: true,
        );
        final expected = [
          'Feature: Background Feature',
          '',
          '  Background:',
          '    Given shared setup',
          '  Scenario: Flow',
          '    Given initial condition',
          '    When action occurs',
          '    Then outcome happens',
          '',
        ].join('\n');

        expect(output, expected);
      });

      test('should render with bold/italic markers when using BddRunner config', () {
        final feature = BddFeature('Background Feature');

        feature.background.given('shared setup');

        final BddFramework bdd = Bdd(feature);
        bdd
            .scenario('Flow')
            .given('initial condition')
            .when('action occurs')
            .then('outcome happens')
            .example(val('NewTime', '14:00'));

        final output = bdd.toString(
          config: BddRunner.config,
          withFeature: true,
        );
        const bi = BddRunner.boldItalic;
        const bo = BddRunner.boldItalicOff;
        const featureKeyword = '${bi}Feature:$bo';
        const givenKeyword = '${bi}Given$bo';
        const scenarioKeyword = '${bi}Scenario Outline:$bo';
        const whenKeyword = '${bi}When$bo';
        const thenKeyword = '${bi}Then$bo';
        const examplesKeyword = '${bi}Examples:$bo';

        final expected = [
          '$featureKeyword Background Feature',
          '',
          '  Background:',
          '    $givenKeyword shared setup',
          '',
          '  $scenarioKeyword Flow',
          '    $givenKeyword initial condition',
          '    $whenKeyword action occurs',
          '    $thenKeyword outcome happens',
          '    $examplesKeyword ',
          '      | NewTime |',
          '      | 14:00   |',
          '',
        ].join('\n');

        expect(output, expected);
      });

      test('should execute Background steps before scenario steps', () async {
        final feature = BddFeature('Background Run Test');
        final log = <String>[];

        feature.background
            .given('background setup')
            .code((_) => log.add('bg1'))
            .and('more background setup')
            .code((_) => log.add('bg2'));

        final bdd = Bdd(feature)
            .scenario('Main Flow')
            .given('initial condition')
            .code((_) => log.add('s1'))
            .when('action occurs')
            .code((_) => log.add('w1'))
            .then('outcome happens')
            .code((_) => log.add('t1'));

        bdd.testRun((_) {
          log.add('runTest_end');
        }, ConsoleReporter());

        expect(log, ['bg1', 'bg2', 's1', 'w1', 't1', 'runTest_end']);
      });
    });
  });
}
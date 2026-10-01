import 'package:bdd_framework/bdd_framework.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('custom Gherkin formatting', () {
    test('Background preserves localized keywords and Unicode text', () {
      final background = BddFeature('背景').background;
      background.given('初始化狀態');
      const config =
          BddConfig(keywords: BddKeywords(background: '背景:', given: '假定'));
      expect(background.toString(config), '  背景:\n    假定 初始化狀態\n');
    });

    test('Background applies keyword prefix and suffix', () {
      final background = BddFeature('prefix and suffix').background;
      const config = BddConfig(
        keywordPrefix: BddKeywords.only(background: '--> '),
        keywordSuffix: BddKeywords.only(background: ' <--'),
      );
      expect(background.toString(config), '  --> Background: <--\n');
    });

    test('Background respects CRLF line endings', () {
      final background = BddFeature('CRLF').background;
      background.given('setup');
      expect(background.toString(const BddConfig(endOfLineChar: '\r\n')),
          '  Background:\r\n    Given setup\r\n');
    });

    test('feature descriptions respect padding, prefixes, suffixes and CRLF',
        () {
      final feature = BddFeature('Login System',
          description: 'Description 1\nDescription 2');
      const config = BddConfig(
        keywords: BddKeywords(feature: '功能:'),
        prefix: BddKeywords.only(feature: '-->'),
        suffix: BddKeywords.only(feature: '<--'),
        endOfLineChar: '\r\n',
        padChar: '\t',
        indent: 1,
      );
      expect(
          feature.toString(config),
          '功能: -->Login System<--\r\n'
          '\t-->Description 1\r\n\tDescription 2<--\r\n');
    });

    test('user story preserves its fields and localized keywords', () {
      final description = FeatureDescription.userStory(
          asA: 'User', iWant: 'to log in', soThat: 'I can access my dashboard');
      expect(description.asA, 'User');
      expect(description.iWant, 'to log in');
      expect(description.soThat, 'I can access my dashboard');
      expect(description.text, isNull);
      const config = BddConfig(
          keywords: BddKeywords(asA: '作為', iWant: '我想要', soThat: '以便'));
      expect(
          description.format(config),
          '  作為 User\n'
          '  我想要 to log in\n  以便 I can access my dashboard\n');
    });

    test('user story respects custom indentation and CRLF', () {
      final description = FeatureDescription.userStory(
          asA: 'Admin',
          iWant: 'to manage users',
          soThat: 'I can control access');
      const config = BddConfig(indent: 1, padChar: '\t', endOfLineChar: '\r\n');
      expect(
          description.format(config),
          '\tAs a Admin\r\n'
          '\tI want to manage users\r\n\tSo that I can control access\r\n');
    });

    test('examples preserve localized headings, values and CRLF', () {
      final examples =
          Bdd().scenario('examples').then('value').example(val('狀態', '好'));
      const config = BddConfig(
          keywords: BddKeywords(examples: '例子:'), endOfLineChar: '\r\n');
      expect(examples.toString(config),
          '    例子: \r\n      | 狀態 |\r\n      | 好  |');
    });
  });
}

import 'package:bdd_framework/dart_test.dart';
import 'package:test/test.dart';

import 'gherkin_support.dart';

void main() {
  group('exported output is valid Gherkin', () {
    test('a user story, background, outline and examples round trip', () async {
      final feature = BddFeature.userStory(
        'Average Price',
        asA: 'Stock Investor',
        iWant: 'to see my portfolio average price updated',
        soThat: 'I can make better investment decisions',
      );
      feature.background.given('The user has 100,000 dollars in cash-balance.');

      final bdd = Bdd(feature)
        ..scenario('Buying and Selling stocks changes the average price.')
            .given(
              'The user has <Quantity> shares of <Ticker> at <At> dollars '
              'each.',
            )
            .when(
              'The user <BuyOrSell> <How many> of these stock at <Price> for '
              'each share.',
            )
            .then(
              'The number of shares becomes <Quantity> plus/minus <How many>.',
            )
            .and('The average price for the stock becomes <Average Price>.')
            .example(
              val('Ticker', 'IBM'),
              val('Quantity', 10),
              val('At', 100.00),
              val('BuyOrSell', 'buy'),
              val('How many', 2),
              val('Price', 50.00),
              val('Average Price', 91.67),
            )
            .example(
              val('Ticker', 'IBM'),
              val('Quantity', 8),
              val('At', 200.00),
              val('BuyOrSell', 'sell'),
              val('How many', 3),
              val('Price', 30.00),
              val('Average Price', 302.00),
            );

      final parsed = parseFeature(await exportFeature([bdd]));

      expect(parsed.errors, isEmpty);
      expect(parsed.keyword, 'Feature');
      expect(parsed.name, 'Average Price');
      expect(parsed.language, 'en');
      expect(
        parsed.description,
        '  As a Stock Investor\n'
        '  I want to see my portfolio average price updated\n'
        '  So that I can make better investment decisions',
      );

      expect(parsed.background?.keyword, 'Background');
      expect(parsed.background?.stepLines, [
        'Given The user has 100,000 dollars in cash-balance.',
      ]);

      final scenario = parsed.scenarios.single;
      expect(scenario.keyword, 'Scenario Outline');
      expect(
        scenario.name,
        'Buying and Selling stocks changes the average price.',
      );
      expect(scenario.stepLines, [
        'Given The user has <Quantity> shares of <Ticker> at <At> dollars each.',
        'When The user <BuyOrSell> <How many> of these stock at <Price> for '
            'each share.',
        'Then The number of shares becomes <Quantity> plus/minus <How many>.',
        'And The average price for the stock becomes <Average Price>.',
      ]);

      final examples = scenario.examples.single;
      expect(examples.keyword, 'Examples');
      expect(examples.name, '');
      expect(examples.table, [
        [
          'Ticker',
          'Quantity',
          'At',
          'BuyOrSell',
          'How many',
          'Price',
          'Average Price',
        ],
        ['IBM', '10', '100.0', 'buy', '2', '50.0', '91.67'],
        ['IBM', '8', '200.0', 'sell', '3', '30.0', '302.0'],
      ]);

      expect(parsed.pickles, hasLength(2));
      expect(parsed.pickles.first.stepTexts, [
        'The user has 100,000 dollars in cash-balance.',
        'The user has 10 shares of IBM at 100.0 dollars each.',
        'The user buy 2 of these stock at 50.0 for each share.',
        'The number of shares becomes 10 plus/minus 2.',
        'The average price for the stock becomes 91.67.',
      ]);
      expect(parsed.pickles.last.stepTexts, [
        'The user has 100,000 dollars in cash-balance.',
        'The user has 8 shares of IBM at 200.0 dollars each.',
        'The user sell 3 of these stock at 30.0 for each share.',
        'The number of shares becomes 8 plus/minus 3.',
        'The average price for the stock becomes 302.0.',
      ]);
    });

    test('data tables, commas and non-ASCII text round trip', () async {
      final feature = BddFeature('Buying and Selling Stocks');
      feature.background.given('The user has 120 dollars in cash-balance.');

      final selling = Bdd(feature)
        ..scenario('Selling stocks.')
            .given('The current stock prices are as such:')
            .table(
              'Available Stocks',
              row(val('Ticker', 'AAPL'), val('Price', 50.25)),
              row(val('Ticker', 'IBM'), val('Price', 30.00)),
              row(val('Ticker', 'GOOG'), val('Price', 60.75)),
            )
            .and('The user Portfolio contains:')
            .table(
              'Portfolio',
              row(val('Ticker', 'AAPL'), val('Quantity', 5)),
              row(val('Ticker', 'IBM'), val('Quantity', 3)),
              row(val('Ticker', 'GOOG'), val('Quantity', 12)),
            )
            .when('The user sells 1 IBM.')
            .then('The user now has 2 IBM.')
            .and('AAPL is still 5, and GOOG is still 12.');

      final missing = Bdd(feature)
        ..scenario('Selling stocks you don\u2019t have.')
            .given('IBM price is 30 dollars.')
            .and('The user has no IBM stocks.')
            .when('The user sells 1 IBM.')
            .then('We get an error.');

      final parsed = parseFeature(await exportFeature([selling, missing]));

      expect(parsed.errors, isEmpty);
      expect(parsed.name, 'Buying and Selling Stocks');
      expect(parsed.description, '');
      expect(parsed.background?.stepLines, [
        'Given The user has 120 dollars in cash-balance.',
      ]);

      expect(parsed.scenarios.map((scenario) => scenario.name), [
        'Selling stocks.',
        'Selling stocks you don\u2019t have.',
      ]);
      expect(
        parsed.scenarios.map((scenario) => scenario.keyword),
        everyElement('Scenario'),
      );

      final first = parsed.scenarios.first;
      expect(first.stepLines, [
        'Given The current stock prices are as such:',
        'And The user Portfolio contains:',
        'When The user sells 1 IBM.',
        'Then The user now has 2 IBM.',
        'And AAPL is still 5, and GOOG is still 12.',
      ]);
      expect(first.steps[0].table, [
        ['Ticker', 'Price'],
        ['AAPL', '50.25'],
        ['IBM', '30.0'],
        ['GOOG', '60.75'],
      ]);
      expect(first.steps[1].table, [
        ['Ticker', 'Quantity'],
        ['AAPL', '5'],
        ['IBM', '3'],
        ['GOOG', '12'],
      ]);
      expect(first.steps[2].table, isNull);

      expect(parsed.pickles, hasLength(2));
      expect(parsed.pickles.first.steps[1].table, [
        ['Ticker', 'Price'],
        ['AAPL', '50.25'],
        ['IBM', '30.0'],
        ['GOOG', '60.75'],
      ]);
      expect(parsed.pickles.last.stepTexts, [
        'The user has 120 dollars in cash-balance.',
        'IBM price is 30 dollars.',
        'The user has no IBM stocks.',
        'The user sells 1 IBM.',
        'We get an error.',
      ]);
    });

    test('background, And and But keywords survive the export', () async {
      final feature = BddFeature('round trip');
      feature.background.given('shared setup');
      final bdd = Bdd(feature)
        ..scenario('a scenario')
            .given('a precondition')
            .and('another precondition')
            .when('an action')
            .then('an outcome')
            .but('an exception');

      final parsed = parseFeature(await exportFeature([bdd]));

      expect(parsed.errors, isEmpty);
      expect(parsed.name, 'round trip');
      expect(parsed.background?.stepLines, ['Given shared setup']);

      final scenario = parsed.scenarios.single;
      expect(scenario.keyword, 'Scenario');
      expect(scenario.name, 'a scenario');
      expect(scenario.stepLines, [
        'Given a precondition',
        'And another precondition',
        'When an action',
        'Then an outcome',
        'But an exception',
      ]);

      expect(parsed.pickles.single.stepTexts, [
        'shared setup',
        'a precondition',
        'another precondition',
        'an action',
        'an outcome',
        'an exception',
      ]);
    });

    test('a single-line note exports as a Gherkin comment, not a step',
        () async {
      final feature = BddFeature('single line note');
      final bdd = Bdd(feature)
        ..scenario('a scenario')
            .given('a precondition')
            .note('a note')
            .then('an outcome');

      final parsed = parseFeature(await exportFeature([bdd]));

      expect(parsed.errors, isEmpty);
      expect(parsed.comments, ['    # A note']);
      expect(parsed.scenarios.single.stepLines, [
        'Given a precondition',
        'Then an outcome',
      ]);
    });

    test('a backslash in a table cell survives the export', () async {
      final feature = BddFeature('backslash cell');
      final bdd = Bdd(feature)
        ..scenario('a scenario')
            .given('a table')
            .table('T', row(val('path', r'C:\tmp')))
            .when('an action')
            .then('an outcome');

      final parsed = parseFeature(await exportFeature([bdd]));

      expect(parsed.errors, isEmpty);
      expect(parsed.scenarios.single.steps.first.table, [
        ['path'],
        [r'C:\tmp'],
      ]);
      expect(parsed.pickles.single.steps.first.table, [
        ['path'],
        [r'C:\tmp'],
      ]);
    });
  });

  group('the exporter escapes cell values', () {
    // https://github.com/marcglasberg/bdd_framework/issues/18
    test('a pipe in a data table cell round trips', () async {
      final feature = BddFeature('pipe in data table');
      final bdd = Bdd(feature)
        ..scenario('a scenario')
            .given('a table')
            .table('T', row(val('cmd', 'ls | grep x')))
            .when('an action')
            .then('an outcome');

      final parsed = parseFeature(await exportFeature([bdd]));

      expect(parsed.errors, isEmpty);
      expect(parsed.scenarios.single.steps.first.table, [
        ['cmd'],
        ['ls | grep x'],
      ]);
      expect(parsed.pickles.single.steps.first.table, [
        ['cmd'],
        ['ls | grep x'],
      ]);
    });

    // https://github.com/marcglasberg/bdd_framework/issues/18
    test('a pipe in an Examples cell round trips', () async {
      final feature = BddFeature('pipe in examples');
      final bdd = Bdd(feature)
        ..scenario('a scenario')
            .given('a value <v>')
            .then('an outcome')
            .example(val('v', 'a|b'));

      final parsed = parseFeature(await exportFeature([bdd]));

      expect(parsed.errors, isEmpty);

      final scenario = parsed.scenarios.single;
      expect(scenario.keyword, 'Scenario Outline');
      expect(scenario.examples.single.table, [
        ['v'],
        ['a|b'],
      ]);
      expect(parsed.pickles.single.stepTexts, ['a value a|b', 'an outcome']);
    });
  });

  group('the exporter handles newlines in text', () {
    // https://github.com/marcglasberg/bdd_framework/issues/19
    test('a newline in step text does not add a scenario', () async {
      final feature = BddFeature('newline in step');
      final bdd = Bdd(feature)
        ..scenario('a scenario')
            .given('line one\nScenario: injected')
            .then('an outcome');

      final parsed = parseFeature(await exportFeature([bdd]));

      expect(parsed.errors, isEmpty);

      // Loose on the `Given` text on purpose: collapsing the newline to a
      // space and moving the text into a DocString are both valid fixes.
      final scenario = parsed.scenarios.single;
      expect(scenario.name, 'a scenario');
      expect(scenario.steps, hasLength(2));
      expect(scenario.steps.first.keyword, 'Given');
      expect(scenario.steps.first.text, contains('line one'));
      expect(scenario.stepLines.last, 'Then an outcome');

      expect(parsed.pickles.single.name, 'a scenario');
      expect(parsed.pickles.single.stepTexts.last, 'an outcome');
    });

    // https://github.com/marcglasberg/bdd_framework/issues/20
    test('a newline in a note comments every line', () async {
      final feature = BddFeature('newline in note');
      final bdd = Bdd(feature)
        ..scenario('a scenario')
            .given('a precondition')
            .note('first line\nsecond line')
            .then('an outcome');

      final parsed = parseFeature(await exportFeature([bdd]));

      expect(parsed.errors, isEmpty);
      expect(
        parsed.comments.map((comment) => comment.trim()),
        ['# First line', '# second line'],
      );
      expect(parsed.scenarios.single.stepLines, [
        'Given a precondition',
        'Then an outcome',
      ]);
    });

    test('a newline in a scenario name or feature title adds nothing',
        () async {
      final feature = BddFeature('title one\nScenario: injected');
      final bdd = Bdd(feature)
        ..scenario('name one\nScenario: injected')
            .given('a precondition')
            .then('an outcome');

      final parsed = parseFeature(await exportFeature([bdd]));

      expect(parsed.errors, isEmpty);
      expect(parsed.name, 'title one Scenario: injected');
      expect(parsed.scenarios.single.name, 'name one Scenario: injected');
      expect(parsed.scenarios.single.stepLines, [
        'Given a precondition',
        'Then an outcome',
      ]);
    });

    test('a newline in a user story keeps each part on its line', () async {
      final feature = BddFeature.userStory(
        'user story',
        asA: 'user\nScenario: injected',
        iWant: 'to\nlog in',
        soThat: 'I\r\ncan work',
      );
      final bdd = Bdd(feature)
        ..scenario('a scenario').given('a precondition').then('an outcome');

      final parsed = parseFeature(await exportFeature([bdd]));

      expect(parsed.errors, isEmpty);
      expect(
        parsed.description,
        '  As a user Scenario: injected\n'
        '  I want to log in\n'
        '  So that I can work',
      );
      expect(parsed.scenarios.single.name, 'a scenario');
    });
  });

  group('cell values with backslashes and line breaks round trip', () {
    // The parser reads `\\`, `\|` and `\n` as escapes. A backslash anywhere
    // else is kept as is, so values like `C:\tmp` need no escaping.
    final values = <String, String>{
      'windows path': r'C:\tmp\new',
      'regex': r'\d+\s*',
      'backslash before a pipe': r'a\|b',
      'two backslashes': r'a\\b',
      'backslash and n': r'a\nb',
      'trailing backslash': r'ends with \',
      'only a backslash': r'\',
      'line break': 'line one\nline two',
      'CRLF line break': 'line one\r\nline two',
      'backslash before a line break': 'a\\\nb',
      'pipes everywhere': '|a||b|',
    };

    for (final MapEntry(key: description, value: value) in values.entries) {
      test('$description, in a data table and in Examples', () async {
        final expected = value.replaceAll('\r\n', '\n');
        final feature = BddFeature('cell values');
        final tableBdd = Bdd(feature)
          ..scenario('a table')
              .given('a table')
              .table('T', row(val('v', value), val(value, 'x')))
              .when('an action')
              .then('an outcome');
        final examplesBdd = Bdd(feature)
          ..scenario('examples')
              .given('a value <v>')
              .then('an outcome')
              .example(val('v', value));

        final parsed =
            parseFeature(await exportFeature([tableBdd, examplesBdd]));

        expect(parsed.errors, isEmpty);
        expect(parsed.scenarios.first.steps.first.table, [
          ['v', expected],
          [expected, 'x'],
        ]);
        expect(parsed.scenarios.last.examples.single.table, [
          ['v'],
          [expected],
        ]);
        expect(parsed.pickles.last.stepTexts.first, 'a value $expected');
      });
    }

    test('values that need no escaping are written unchanged', () async {
      final feature = BddFeature('unchanged');
      final bdd = Bdd(feature)
        ..scenario('a scenario')
            .given('a table')
            .table('T', row(val('path', r'C:\tmp'), val('regex', r'\d+')))
            .when('an action')
            .then('an outcome');

      final text = await exportFeature([bdd]);

      expect(text, contains(r'      | path   | regex |' '\n'));
      expect(text, contains(r'      | C:\tmp | \d+   |' '\n'));
    });

    test('escaped values keep the columns aligned', () async {
      final feature = BddFeature('aligned');
      final bdd = Bdd(feature)
        ..scenario('a scenario')
            .given('a table')
            .table(
              'T',
              row(val('cmd', 'ls | grep x'), val('n', 1)),
              row(val('cmd', 'pwd'), val('n', 2)),
            )
            .when('an action')
            .then('an outcome');

      final text = await exportFeature([bdd]);

      expect(
        text,
        contains('      | cmd          | n |\n'
            r'      | ls \| grep x | 1 |'
            '\n'
            '      | pwd          | 2 |\n'),
      );
    });
  });
}

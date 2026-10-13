import 'package:bdd_framework/dart_test.dart';
import 'package:test/test.dart';

import 'gherkin_support.dart';

/// Checks the `.feature` files produced by [FeatureFileReporter] against the
/// official Gherkin grammar, using `cucumber_gherkin` as a dev dependency.
///
/// Every feature here is built with the public BDD API and exported at run
/// time, then parsed. Nothing reads a checked-in `.feature` file, so the suite
/// covers the exporter itself rather than a stale artifact, and it does not
/// depend on `example/` or on the working directory.
///
/// Every test asserts the *structure* the parser built, not merely that
/// parsing succeeded. That distinction matters: the newline-in-step-text bug
/// below parses without error yet silently yields the wrong scenarios, so a
/// test that only checked for parse errors would pass while the export is
/// broken.
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

      final parsed = parseFeature(await exportFeature(feature, [bdd]));

      expect(parsed.errors, isEmpty);
      expect(parsed.keyword, 'Feature');
      expect(parsed.name, 'Average Price');
      expect(parsed.language, 'en');

      // `BddFeature.userStory` becomes the free-form feature description.
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

      // `.example(...)` must promote `Scenario:` to `Scenario Outline:`.
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

      // Both `.example(...)` calls must collapse into one Examples table,
      // header first, with `int` and `double` cells rendered by `toString`.
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

      // One pickle per Examples row, with `<placeholders>` substituted and the
      // Background step prepended. Placeholder names containing spaces, such
      // as `<How many>`, must resolve too.
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

    test('data tables and non-ASCII text round trip', () async {
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
            // A comma in step text must not be mistaken for a cell separator.
            .and('AAPL is still 5, and GOOG is still 12.');

      final missing = Bdd(feature)
        ..scenario('Selling stocks you don\u2019t have.')
            .given('IBM price is 30 dollars.')
            .and('The user has no IBM stocks.')
            .when('The user sells 1 IBM.')
            .then('We get an error.');

      final parsed = parseFeature(
        await exportFeature(feature, [selling, missing]),
      );

      expect(parsed.errors, isEmpty);
      expect(parsed.name, 'Buying and Selling Stocks');
      expect(parsed.description, '');
      expect(parsed.background?.stepLines, [
        'Given The user has 120 dollars in cash-balance.',
      ]);

      // Two BDDs sharing one feature must export as two scenarios under a
      // single `Feature:`, in declaration order.
      expect(parsed.scenarios.map((scenario) => scenario.name), [
        'Selling stocks.',
        // Non-ASCII right single quote (U+2019) must survive the round trip.
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

      // Each `.table(...)` must attach to the step it was chained onto.
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

      final parsed = parseFeature(await exportFeature(feature, [bdd]));

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

      // The Background step is prepended to the pickle, and `And` / `But`
      // inherit the preceding keyword rather than appearing verbatim.
      expect(parsed.pickles.single.stepTexts, [
        'shared setup',
        'a precondition',
        'another precondition',
        'an action',
        'an outcome',
        'an exception',
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

      final parsed = parseFeature(await exportFeature(feature, [bdd]));

      // Gherkin only gives `\|`, `\\` and `\n` meaning inside a cell, so an
      // unrecognised escape such as `\t` passes through untouched.
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

  // ---------------------------------------------------------------------------
  // The tests below pin the CURRENT, INCORRECT behaviour so the bugs are
  // covered and any change to them is visible in a diff. Each one states the
  // behaviour it should have instead. When a fix lands, invert the assertion
  // to the documented expectation and move the test out of this group.
  //
  // See https://github.com/marcglasberg/bdd_framework/issues/17
  // ---------------------------------------------------------------------------
  group('known issues: the exporter does not escape cell values', () {
    test('KNOWN ISSUE: a pipe in a data table cell produces invalid Gherkin',
        () async {
      final feature = BddFeature('pipe in data table');
      final bdd = Bdd(feature)
        ..scenario('a scenario')
            .given('a table')
            .table('T', row(val('cmd', 'ls | grep x')))
            .when('an action')
            .then('an outcome');

      final parsed = parseFeature(await exportFeature(feature, [bdd]));

      // SHOULD BE: parsed.errors is empty, and the single cell holds
      // 'ls | grep x', which requires the exporter to write `ls \| grep x`.
      expect(parsed.isValid, isFalse);
      expect(
        parsed.errors.single,
        contains('inconsistent cell count within the table'),
      );

      // The parse failure means no usable structure at all.
      expect(parsed.scenarios, isEmpty);
      expect(parsed.pickles, isEmpty);
    });

    test('KNOWN ISSUE: a pipe in an Examples cell produces invalid Gherkin',
        () async {
      final feature = BddFeature('pipe in examples');
      final bdd = Bdd(feature)
        ..scenario('a scenario')
            .given('a value <v>')
            .then('an outcome')
            .example(val('v', 'a|b'));

      final parsed = parseFeature(await exportFeature(feature, [bdd]));

      // SHOULD BE: parsed.errors is empty, the Examples body row is ['a|b'],
      // and one pickle is produced.
      expect(parsed.isValid, isFalse);
      expect(
        parsed.errors.single,
        contains('inconsistent cell count within the table'),
      );
      expect(parsed.scenarios, isEmpty);
      expect(parsed.pickles, isEmpty);
    });
  });

  group('known issues: the exporter does not handle newlines in text', () {
    test('KNOWN ISSUE: a newline in step text silently adds a scenario',
        () async {
      final feature = BddFeature('newline in step');
      final bdd = Bdd(feature)
        ..scenario('a scenario')
            .given('line one\nScenario: injected')
            .then('an outcome');

      final parsed = parseFeature(await exportFeature(feature, [bdd]));

      // This is the case a parse-only check cannot catch: the output is valid
      // Gherkin, but it does not describe the test that was written.
      expect(parsed.isValid, isTrue);

      // SHOULD BE: one scenario named 'a scenario' holding both steps, and
      // exactly one pickle.
      expect(parsed.scenarios, hasLength(2));
      expect(
        parsed.scenarios.map((scenario) => scenario.name),
        ['a scenario', 'injected'],
      );

      // The `Then` step was captured by the injected scenario, so the first
      // scenario lost it entirely.
      expect(parsed.scenarios.first.stepLines, ['Given line one']);
      expect(parsed.scenarios.last.stepLines, ['Then an outcome']);

      expect(parsed.pickles, hasLength(2));
      expect(
        parsed.pickles.map((pickle) => pickle.name),
        ['a scenario', 'injected'],
      );
    });

    test('KNOWN ISSUE: a newline in a note produces invalid Gherkin', () async {
      final feature = BddFeature('newline in note');
      final bdd = Bdd(feature)
        ..scenario('a scenario')
            .given('a precondition')
            .note('first line\nsecond line')
            .then('an outcome');

      final parsed = parseFeature(await exportFeature(feature, [bdd]));

      // Only the first line gets the `#` comment marker, so the second line is
      // emitted as bare text.
      //
      // SHOULD BE: parsed.errors is empty and parsed.comments holds the whole
      // note, with every line commented.
      expect(parsed.isValid, isFalse);
      expect(parsed.errors.single, contains("got 'second line'"));
      expect(parsed.scenarios, isEmpty);
    });
  });
}

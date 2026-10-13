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
/// parsing succeeded. That distinction matters: the newline-in-step-text case
/// below parses without error yet silently yields the wrong scenarios, so a
/// test that only checked for parse errors would pass while the export is
/// broken.
///
/// Every test also asserts the behaviour the exporter *should* have, never the
/// behaviour it currently has. The cases it gets wrong are marked `skip` with
/// the defect named, so a passing run cannot be read as a claim that those
/// cases work. Removing a `skip` is the whole of the test-side change when a
/// fix lands.
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

    test('a single-line note exports as a Gherkin comment', () async {
      final feature = BddFeature('single line note');
      final bdd = Bdd(feature)
        ..scenario('a scenario')
            .given('a precondition')
            .note('a note')
            .then('an outcome');

      final parsed = parseFeature(await exportFeature(feature, [bdd]));

      // `note()` capitalizes the first character and prefixes the line with
      // `#`, so the parser reports it as a comment and not as a step. This is
      // the baseline that the multi-line note further down deviates from.
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
  // The tests below assert the behaviour the exporter SHOULD have. They are
  // skipped because it does not have it yet.
  //
  // They are written this way round on purpose. A test that asserted the
  // current, broken output would pass, and a green suite would then read as
  // "the exporter handles these cases" when it does not. Skipped tests that
  // hold the target behaviour keep the expectation as the source of truth:
  // green never certifies a bug, and a fix turns a test green rather than red.
  //
  // Each `skip` reason names the defect. When a fix lands, delete the `skip`;
  // the assertions are already the ones it has to satisfy.
  //
  // The trade-off: while skipped, nothing here guards the current output, so a
  // regression that changes it in some other way goes unnoticed. That is the
  // intended cost of not overstating what the suite verifies.
  //
  // Each test names the issue tracking it.
  // ---------------------------------------------------------------------------
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

      final parsed = parseFeature(await exportFeature(feature, [bdd]));

      // Requires the exporter to write `ls \| grep x`. It currently writes the
      // pipe raw, which splits one body cell into three against a one-column
      // header and fails the parse on the cell count.
      expect(parsed.errors, isEmpty);
      expect(parsed.scenarios.single.steps.first.table, [
        ['cmd'],
        ['ls | grep x'],
      ]);
      expect(parsed.pickles.single.steps.first.table, [
        ['cmd'],
        ['ls | grep x'],
      ]);
    }, skip: 'The exporter does not escape `|` in data table cells.');

    // https://github.com/marcglasberg/bdd_framework/issues/18
    test('a pipe in an Examples cell round trips', () async {
      final feature = BddFeature('pipe in examples');
      final bdd = Bdd(feature)
        ..scenario('a scenario')
            .given('a value <v>')
            .then('an outcome')
            .example(val('v', 'a|b'));

      final parsed = parseFeature(await exportFeature(feature, [bdd]));

      expect(parsed.errors, isEmpty);

      final scenario = parsed.scenarios.single;
      expect(scenario.keyword, 'Scenario Outline');
      expect(scenario.examples.single.table, [
        ['v'],
        ['a|b'],
      ]);

      // The pickle matters here: the escape has to survive placeholder
      // substitution, so `<v>` resolves to the pipe and not to `a\|b`.
      expect(parsed.pickles.single.stepTexts, ['a value a|b', 'an outcome']);
    }, skip: 'The exporter does not escape `|` in Examples cells.');
  });

  group('the exporter handles newlines in text', () {
    // https://github.com/marcglasberg/bdd_framework/issues/19
    test('a newline in step text does not add a scenario', () async {
      final feature = BddFeature('newline in step');
      final bdd = Bdd(feature)
        ..scenario('a scenario')
            .given('line one\nScenario: injected')
            .then('an outcome');

      final parsed = parseFeature(await exportFeature(feature, [bdd]));

      // The output is currently valid Gherkin that describes a different test
      // than the one written: the embedded newline lets `Scenario: injected`
      // open a second scenario, which captures the `Then` and leaves the first
      // scenario holding only the `Given`. This is why the suite asserts
      // structure rather than parse success.
      expect(parsed.errors, isEmpty);

      final scenario = parsed.scenarios.single;
      expect(scenario.name, 'a scenario');
      expect(scenario.steps, hasLength(2));
      expect(scenario.steps.first.keyword, 'Given');
      expect(scenario.steps.first.text, contains('line one'));
      expect(scenario.stepLines.last, 'Then an outcome');

      expect(parsed.pickles.single.name, 'a scenario');
      expect(parsed.pickles.single.stepTexts.last, 'an outcome');

      // What the newline itself becomes is deliberately not pinned: collapsing
      // it to a space and moving the text into a DocString are both valid
      // fixes, and they differ only in the `Given` text. A DocString fix would
      // additionally need `ParsedStep` to expose one. The invariant asserted
      // here is the one both must satisfy: one scenario, one pickle, and no
      // step lost.
    },
        skip: 'The exporter writes newlines in step text raw, '
            'so text after one can open a second scenario.');

    // https://github.com/marcglasberg/bdd_framework/issues/20
    test('a newline in a note comments every line', () async {
      final feature = BddFeature('newline in note');
      final bdd = Bdd(feature)
        ..scenario('a scenario')
            .given('a precondition')
            .note('first line\nsecond line')
            .then('an outcome');

      final parsed = parseFeature(await exportFeature(feature, [bdd]));

      // Every line of the note must carry its own `#`, as the single-line note
      // above does. Only the first line currently gets one, so the second is
      // emitted as bare text and the parse error costs the whole file: not
      // even line one survives as the comment it was written as.
      //
      // Indentation is not pinned, only the comment text. `note()` capitalizes
      // the first character of the note, which is why line one is `First`.
      expect(parsed.errors, isEmpty);
      expect(
        parsed.comments.map((comment) => comment.trim()),
        ['# First line', '# second line'],
      );
      expect(parsed.scenarios.single.stepLines, [
        'Given a precondition',
        'Then an outcome',
      ]);
    }, skip: 'The exporter only prefixes the first line of a note with `#`.');
  });
}

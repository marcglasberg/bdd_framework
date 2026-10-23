// Pins the exact text the reporters produce today for a feature that uses
// every kind of step, table, note and example. If any formatting changes,
// these tests show exactly what changed.
import 'package:bdd_framework/dart_test.dart';
import 'package:test/test.dart';

import 'gherkin_support.dart';
import 'stdout_capture.dart';

void main() {
  test('the .feature file for a feature using every term', () async {
    final text = await exportFeature(_buildPortfolio());

    expect(text, _expectedFeatureFile);
    expect(parseFeature(text).errors, isEmpty);
  });

  test('the ConsoleReporter output for a feature using every term', () async {
    final output = await captureStdout(() async {
      final reporter = ConsoleReporter();
      BddReporter.set(reporter);
      try {
        for (final bdd in _buildPortfolio()) {
          BddRunner().run(bdd, (_) {}, (_) {}, null);
        }
        await reporter.report();
      } finally {
        BddReporter.set();
      }
    });

    expect(output, _expectedConsoleOutput);
  });
}

/// Builds a fresh feature each time, since [BddFeature] keeps every BDD added
/// to it.
List<BddFramework> _buildPortfolio() {
  final feature = BddFeature.userStory(
    'Portfolio',
    asA: 'Stock Investor',
    iWant: 'to track my stocks',
    soThat: 'I know what I own',
  );
  feature.background
      .given('The user is logged in.')
      .table('Account', row(val('Name', 'Ana'), val('Cash', 120)))
      .note('a background note.');

  final selling = Bdd(feature)
    ..scenario('Selling stocks.')
        .given('Prices are:')
        .table(
          'Prices',
          row(val('Ticker', 'AAPL'), val('Price', 50.25)),
          row(val('Ticker', 'IBM'), val('Price', 30)),
        )
        .and('The user owns 3 IBM.')
        .but('The market is closed.')
        .note('a given note.')
        .when('The user sells 1 IBM.')
        .table(
          'Order',
          row(val('Path', r'C:\orders\ibm.json'), val('Regex', r'\d+')),
        )
        .and('The user confirms.')
        .but('Only once.')
        .note('ação em português.')
        .then('The user owns 2 IBM.')
        .table('Result', row(val('Ticker', 'IBM'), val('Qty', 2)))
        .and('AAPL is unchanged.')
        .but('No fee is charged.')
        .note('a then note.');

  final buying = Bdd(feature)
    ..scenario('Buying <Ticker>.')
        .given('The user has <Cash> dollars.')
        .when('The user buys <Qty> <Ticker>.')
        .then('The user has <Left> dollars.')
        .example(
          val('Ticker', 'IBM'),
          val('Cash', 100),
          val('Qty', 2),
          val('Left', 40.5),
        )
        .example(
          val('Ticker', 'ÇÃO'),
          val('Cash', 1000),
          val('Qty', 10),
          val('Left', 0),
        );

  return [selling, buying];
}

const _expectedFeatureFile = 'Feature: Portfolio\n'
    '  As a Stock Investor\n'
    '  I want to track my stocks\n'
    '  So that I know what I own\n'
    '\n'
    '  Background:\n'
    '    Given The user is logged in.\n'
    '      | Name | Cash |\n'
    '      | Ana  | 120  |\n'
    '    # A background note.\n'
    '\n'
    '  Scenario: Selling stocks.\n'
    '    Given Prices are:\n'
    '      | Ticker | Price |\n'
    '      | AAPL   | 50.25 |\n'
    '      | IBM    | 30    |\n'
    '    And The user owns 3 IBM.\n'
    '    But The market is closed.\n'
    '    # A given note.\n'
    '    When The user sells 1 IBM.\n'
    '      | Path               | Regex |\n'
    r'      | C:\orders\ibm.json | \d+   |'
    '\n'
    '    And The user confirms.\n'
    '    But Only once.\n'
    '    # Ação em português.\n'
    '    Then The user owns 2 IBM.\n'
    '      | Ticker | Qty |\n'
    '      | IBM    | 2   |\n'
    '    And AAPL is unchanged.\n'
    '    But No fee is charged.\n'
    '    # A then note.\n'
    '\n'
    '  Scenario Outline: Buying <Ticker>.\n'
    '    Given The user has <Cash> dollars.\n'
    '    When The user buys <Qty> <Ticker>.\n'
    '    Then The user has <Left> dollars.\n'
    '    Examples: \n'
    '      | Ticker | Cash | Qty | Left |\n'
    '      | IBM    | 100  | 2   | 40.5 |\n'
    '      | ÇÃO    | 1000 | 10  | 0    |\n';

const _expectedConsoleOutput = 'BddFeature 1 --------------\n'
    '\n'
    'Feature: Portfolio\n'
    '  As a Stock Investor\n'
    '  I want to track my stocks\n'
    '  So that I know what I own\n'
    '\n'
    '  Background:\n'
    '    Given The user is logged in.\n'
    '          | Name | Cash |\n'
    '          | Ana  | 120  |\n'
    '        # A background note.\n'
    '\n'
    '  Scenario: Selling stocks.\n'
    '    Given Prices are:\n'
    '          | Ticker | Price |\n'
    '          | AAPL   | 50.25 |\n'
    '          | IBM    | 30    |\n'
    '      And The user owns 3 IBM.\n'
    '      But The market is closed.\n'
    '        # A given note.\n'
    '     When The user sells 1 IBM.\n'
    '          | Path               | Regex |\n'
    r'          | C:\orders\ibm.json | \d+   |'
    '\n'
    '      And The user confirms.\n'
    '      But Only once.\n'
    '        # Ação em português.\n'
    '     Then The user owns 2 IBM.\n'
    '          | Ticker | Qty |\n'
    '          | IBM    | 2   |\n'
    '      And AAPL is unchanged.\n'
    '      But No fee is charged.\n'
    '        # A then note.\n'
    '\n'
    '\n'
    '  Scenario Outline: Buying <Ticker>.\n'
    '    Given The user has <Cash> dollars.\n'
    '     When The user buys <Qty> <Ticker>.\n'
    '     Then The user has <Left> dollars.\n'
    '    Examples: \n'
    '          | Ticker | Cash | Qty | Left |\n'
    '          | IBM    | 100  | 2   | 40.5 |\n'
    '          | ÇÃO    | 1000 | 10  | 0    |\n'
    '\n'
    '\n';

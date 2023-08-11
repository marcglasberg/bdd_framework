import 'package:bdd_framework/bdd_framework.dart';
import 'package:example/business_classes.dart';
import 'package:example/main.dart';
import "package:flutter_test/flutter_test.dart";

void main() {
  var feature = BddFeature('Buying and Selling Stocks');

  Bdd(feature)
      .scenario('Buying stocks.')
      .given('The user has 120 dollars in cash-balance.')
      .and('IBM price is 30 dollars.')
      .and('The user has no IBM stocks.')
      .when('The user buys 1 IBM.')
      .then('The user now has 1 IBM.')
      .and('The cash-balance is now 90 dollars.')
      .run((ctx) async {
    state = AppState.initialState();

    // Given:
    state.portfolio.cashBalance.set(120.00);
    var ibm = state.availableStocks.findBySymbol('IBM');
    ibm.setCurrentPrice(30.00);
    state.portfolio.clearStock('IBM');

    // When:
    state.portfolio.buy(ibm);

    // Then:
    expect(state.portfolio.howManyStocks('IBM'), 1);
    expect(state.portfolio.cashBalance, CashBalance(90.00));
  });

  Bdd(feature)
      .scenario('Selling stocks.')
      .given('The user has 120 dollars in cash-balance.')
      .and('The current stock prices are as such:')
      .table(
        'Available Stocks',
        row(val('Symbol', 'APPL'), val('Price', 50.25)),
        row(val('Symbol', 'IBM'), val('Price', 30.00)),
        row(val('Symbol', 'GOOG'), val('Price', 60.75)),
      )
      .and('The user Portfolio contains:')
      .table(
        'Portfolio',
        row(val('Symbol', 'APPL'), val('Quantity', 5)),
        row(val('Symbol', 'IBM'), val('Quantity', 3)),
        row(val('Symbol', 'GOOG'), val('Quantity', 12)),
      )
      .when('The user sells 1 IBM.')
      .then('The user now has 2 IBM.')
      .and('APPL is still 5, and GOOG is still 12.')
      .and('The cash-balance is now 150 dollars.')
      .run((ctx) async {
    state = AppState.initialState();

    // Given:
    state.portfolio.cashBalance.set(120.00);

    // We read and create the info from the "Available Stocks" table:

    var availableStocksTable = ctx.table('Available Stocks').rows;

    for (var row in availableStocksTable) {
      String symbol = row.val('Symbol');
      double price = row.val('Price');

      var stock = state.availableStocks.findBySymbol(symbol);
      stock.setCurrentPrice(price);
    }

    // We read and create the info from the "Portfolio" table:

    var portfolioTable = ctx.table('Portfolio').rows;

    for (var row in portfolioTable) {
      String symbol = row.val('Symbol');
      int quantity = row.val('Quantity');
      state.portfolio.set(symbol, quantity: quantity, averagePrice: 100);
    }

    // When:
    var ibm = state.availableStocks.findBySymbol('IBM');
    state.portfolio.sell(ibm);

    // Then:
    expect(state.portfolio.howManyStocks('IBM'), 2);
    expect(state.portfolio.howManyStocks('APPL'), 5);
    expect(state.portfolio.howManyStocks('GOOG'), 12);
    expect(state.portfolio.howManyStocks('GOOG'), 122);
    expect(state.portfolio.cashBalance, CashBalance(150.00));

    /// The code below shows the alternative hard-coded implementation:
    //   state = AppState.initialState();
    //
    //   // Given:
    //   state.portfolio.cashBalance.set(120.00);
    //
    //   var appl = state.availableStocks.findBySymbol('APPL');
    //   var ibm = state.availableStocks.findBySymbol('IBM');
    //   var goog = state.availableStocks.findBySymbol('GOOG');
    //
    //   appl.setCurrentPrice(50.25);
    //   ibm.setCurrentPrice(30.00);
    //   goog.setCurrentPrice(60.75);
    //
    //   state.portfolio.set('APPL', quantity: 5, averagePrice: 100);
    //   state.portfolio.set('IBM', quantity: 3, averagePrice: 100);
    //   state.portfolio.set('GOOG', quantity: 12, averagePrice: 100);
    //
    //   // When:
    //   state.portfolio.sell(ibm);
    //
    //   // Then:
    //   expect(state.portfolio.howManyStocks('IBM'), 2);
    //   expect(state.portfolio.howManyStocks('APPL'), 5);
    //   expect(state.portfolio.howManyStocks('GOOG'), 12);
    //   expect(state.portfolio.cashBalance, CashBalance(150.00));
  });

  Bdd(feature)
      .scenario('Selling stocks you don’t have.')
      .given('The user has 120 dollars in cash-balance.')
      .and('IBM price is 30 dollars.')
      .and('The user has no IBM stocks.')
      .when('The user sells 1 IBM.')
      .then('We get an error.')
      .and('The user continues to have 0 IBM.')
      .and('The cash-balance continues to be 120 dollars.')
      .run((ctx) async {
    state = AppState.initialState();

    // Given:
    state.portfolio.cashBalance.set(120.00);
    var ibm = state.availableStocks.findBySymbol('IBM');
    ibm.setCurrentPrice(30.00);
    state.portfolio.clearStock('IBM');

    // When/Then:
    expect(() => state.portfolio.sell(ibm), throwsException);

    // Then:
    expect(state.portfolio.howManyStocks('IBM'), 0);
    expect(state.portfolio.cashBalance, CashBalance(120.00));
  });
}

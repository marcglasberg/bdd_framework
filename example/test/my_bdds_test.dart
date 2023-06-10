import 'package:bdd_framework/bdd_framework.dart';
import 'package:example/business_classes.dart';
import 'package:example/main.dart';
import "package:flutter_test/flutter_test.dart";

void main() {
  var feature = BddFeature('Buying and Selling Stocks');

  Bdd(feature)
      .scenario('Buying stocks.')
      .given('The user has 120 dollars of cash-balance.')
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
      .given('The user has 120 dollars of cash-balance.')
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
    expect(state.portfolio.cashBalance, CashBalance(150.00));
  });

  Bdd(feature)
      .scenario('Selling stocks you don’t have.')
      .given('The user has 120 dollars of cash-balance.')
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

  Bdd(feature)
      .scenario('Buying and Selling stocks changes the average price.')
      .given('The user has <Quantity> shares of <Symbol> at <At> dollars each.')
      .when('The user <BuyOrSell> <How many> of these stock '
          'at <Price> for each share.')
      .then('The number of shares is becomes <Quantity> plus/minus <How many>.')
      .and('The average price for the stock becomes <Average Price>.')
      // Avg price = (10 x 100 + 2 * 50) / 12 = 91.67 dollars.
      .example(
        val('Symbol', 'IBM'),
        val('Quantity', 10),
        val('At', 100.00),
        val('BuyOrSell', BuyOrSell.buy),
        val('How many', 2),
        val('Price', 50.00),
        val('Average Price', 91.67),
      )
      // Avg price =  (1600 - 3 * 30) / (8 - 3) = 302.00 dollars.
      .example(
        val('Symbol', 'IBM'),
        val('Quantity', 8),
        val('At', 200.00),
        val('BuyOrSell', BuyOrSell.sell),
        val('How many', 3),
        val('Price', 30.00),
        val('Average Price', 302.00),
      )
      .run((ctx) async {
    state = AppState.initialState();

    String symbol = ctx.example.val('Symbol');
    int quantity = ctx.example.val('Quantity');
    double at = ctx.example.val('At');
    BuyOrSell buyOrSell = ctx.example.val('BuyOrSell');
    int how = ctx.example.val('How many');
    double price = ctx.example.val('Price');
    double averagePrice = ctx.example.val('Average Price');

    // Sets up everything and just make sure we have money to buy whatever we need.
    state = AppState.initialState();
    state.portfolio.cashBalance.set(100000.00);

    // Given:
    var availableStock = state.availableStocks.findBySymbol(symbol);
    availableStock.setCurrentPrice(at);
    state.portfolio.set(symbol, quantity: quantity, averagePrice: at);

    // when:
    availableStock.setCurrentPrice(price);
    state.portfolio.buyOrSell(availableStock, buyOrSell, howMany: how);

    // Then:
    expect(state.portfolio.howManyStocks(symbol),
        quantity + (buyOrSell.isBuy ? how : -how));

    expect(state.portfolio.getStock(symbol)!.averagePrice, averagePrice);
  });
}

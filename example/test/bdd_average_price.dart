import 'package:bdd_framework/bdd_framework.dart';
import 'package:example/business_classes.dart';
import 'package:example/main.dart';
import "package:flutter_test/flutter_test.dart";

void main() {
  var feature = BddFeature('Average Price');

  Bdd(feature)
      .scenario('Buying and Selling stocks changes the average price.')
      .given('The user has <Quantity> shares of <Ticker> at <At> dollars each.')
      .when(
          'The user <BuyOrSell> <How many> of these stock at <Price> for each share.')
      .then('The number of shares becomes <Quantity> plus/minus <How many>.')
      .and('The average price for the stock becomes <Average Price>.')
      // Avg price = (10 x 100 + 2 * 50) / 12 = 91.67 dollars.
      .example(
        val('Ticker', 'IBM'),
        val('Quantity', 10),
        val('At', 100.00),
        val('BuyOrSell', BuyOrSell.buy),
        val('How many', 2),
        val('Price', 50.00),
        val('Average Price', 91.67),
      )
      // Avg price =  (1600 - 3 * 30) / (8 - 3) = 302.00 dollars.
      .example(
        val('Ticker', 'IBM'),
        val('Quantity', 8),
        val('At', 200.00),
        val('BuyOrSell', BuyOrSell.sell),
        val('How many', 3),
        val('Price', 30.00),
        val('Average Price', 302.00),
      )
      .run((ctx) async {
    //
    String ticker = ctx.example.val('Ticker');
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
    var availableStock = state.availableStocks.findBySymbol(ticker);
    availableStock.setCurrentPrice(at);
    state.portfolio
        .setStockInPortfolio(ticker, quantity: quantity, averagePrice: at);

    // When:
    availableStock.setCurrentPrice(price);
    state.portfolio.buyOrSell(availableStock, buyOrSell, howMany: how);

    // Then:
    expect(state.portfolio.howManyStocks(ticker),
        quantity + (buyOrSell.isBuy ? how : -how));
    expect(state.portfolio.getStock(ticker)!.averagePrice, averagePrice);
  });
}

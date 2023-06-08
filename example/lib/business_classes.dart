// ignore_for_file: curly_braces_in_flow_control_structures

import 'dart:math';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';

/// Round the value to 2 decimal places.
double _round(double value) => double.parse((value).toStringAsFixed(2));

enum BuyOrSell {
  buy,
  sell;

  @override
  String toString() => name;

  bool get isBuy => this == buy;
}

class Stock {
  String symbol;
  int howManyShares;
  double averagePrice;

  Stock({
    required this.symbol,
    required this.howManyShares,
    required this.averagePrice,
  });

  double get costBasis => howManyShares * averagePrice;

  String get averagePriceStr => 'US\$ ${averagePrice.toStringAsFixed(2)}';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Stock &&
          runtimeType == other.runtimeType &&
          symbol == other.symbol &&
          howManyShares == other.howManyShares &&
          averagePrice == other.averagePrice;

  @override
  int get hashCode => symbol.hashCode ^ howManyShares.hashCode ^ averagePrice.hashCode;
}

class CashBalance {
  double _amount;

  double get amount => _amount;

  CashBalance(this._amount);

  void set(double howMuchMoney) {
    _amount = _round(howMuchMoney);
  }

  void add(double howMuchMoney) {
    _amount = _round(_amount + howMuchMoney);
  }

  void remove(double howMuchMoney) {
    _amount = _round(_amount - howMuchMoney);
    if (_amount < 0) _amount = 0;
  }

  @override
  String toString() => 'US\$ $amount';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CashBalance && runtimeType == other.runtimeType && _amount == other._amount;

  @override
  int get hashCode => _amount.hashCode;
}

class Portfolio {
  List<Stock> stocks;
  CashBalance cashBalance;

  Portfolio({
    required this.stocks,
    required this.cashBalance,
  });

  void clearStock(String symbol) => set(symbol, quantity: 0, averagePrice: 0);

  void set(
    String symbol, {
    required int quantity,
    required double averagePrice,
  }) {
    stocks.removeWhere((var stock) => stock.symbol == symbol);

    if (quantity > 0) {
      stocks.add(Stock(symbol: symbol, howManyShares: quantity, averagePrice: averagePrice));
    }
  }

  int howManyStocks(String symbol) {
    var stock = getStock(symbol);
    return stock?.howManyShares ?? 0;
  }

  Stock? getStock(String symbol) => stocks.firstWhereOrNull((var stock) => stock.symbol == symbol);

  /// Returns true if the portfolio contains the given stock.
  bool hasStock(AvailableStock availableStock) => _getStockPositionInList(availableStock) != -1;

  /// Returns true if the portfolio has enough money to buy one share of the given stock.
  bool hasMoneyToBuyStock(AvailableStock availableStock) =>
      cashBalance.amount >= availableStock.currentPrice;

  /// Will [buyOrSell] the amount of [howMany] shares of the given [availableStock].
  void buyOrSell(AvailableStock availableStock, BuyOrSell buyOrSell, {int howMany = 1}) {
    if (buyOrSell.isBuy) {
      buy(availableStock, howMany: howMany);
    } else {
      sell(availableStock, howMany: howMany);
    }
  }

  /// Buy [howMany] shares of the given [availableStock].
  void buy(AvailableStock availableStock, {int howMany = 1}) {
    //
    if (cashBalance.amount < (availableStock.currentPrice * howMany)) {
      throw Exception('Not enough money to buy stock');
    }
    //
    else {
      cashBalance.remove(availableStock.currentPrice * howMany);

      int pos = _getStockPositionInList(availableStock);

      if (pos == -1) {
        stocks.add(availableStock.toStock(shares: howMany));
      } else {
        Stock stock = stocks[pos];

        int newShares = stock.howManyShares + howMany;

        stock.averagePrice = _round(
            ((stock.howManyShares * stock.averagePrice) + (howMany * availableStock.currentPrice)) /
                newShares);

        stock.howManyShares = newShares;
      }
    }
  }

  /// Sell one share of the given stock.
  /// Throws an exception if you do not own the stock.
  void sell(AvailableStock availableStock, {int howMany = 1}) {
    int pos = _getStockPositionInList(availableStock);

    if (pos == -1) {
      throw Exception('Cannot sell stock you do not own');
    }
    //
    else {
      Stock stock = stocks[pos];

      if (stock.howManyShares < howMany)
        throw Exception('Cannot sell $howMany shares of stock you do not own');
      //
      else if (stock.howManyShares == howMany)
        stocks.removeAt(pos);
      //
      else {
        int newShares = stock.howManyShares - howMany;

        stock.averagePrice = _round(
            ((stock.howManyShares * stock.averagePrice) - (howMany * availableStock.currentPrice)) /
                newShares);

        stock.howManyShares = newShares;
      }

      cashBalance.add(availableStock.currentPrice * howMany);
    }
  }

  int _getStockPositionInList(AvailableStock availableStock) =>
      stocks.indexWhere((s) => s.symbol == availableStock.symbol);

  double get totalCostBasis =>
      stocks.fold(0.0, (sum, stock) => sum + stock.costBasis) + cashBalance.amount;

  bool get isEmpty => stocks.isEmpty;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Portfolio &&
          runtimeType == other.runtimeType &&
          listEquals(stocks, other.stocks) &&
          cashBalance == other.cashBalance;

  @override
  int get hashCode => stocks.hashCode ^ cashBalance.hashCode;
}

class AvailableStock {
  String symbol;
  String name;
  double _currentPrice;

  AvailableStock(
    this.symbol, {
    required this.name,
    required double currentPrice,
  }) : _currentPrice = currentPrice;

  String get currentPriceStr => 'US\$ ${_currentPrice.toStringAsFixed(2)}';

  Stock toStock({int shares = 1}) => Stock(
        symbol: symbol,
        howManyShares: shares,
        averagePrice: _currentPrice,
      );

  void fluctuatePrice() {
    double newPrice = _round(_currentPrice + Random().nextDouble() / 5);

    // Limit stock price to between US$ 1 and US$ 1000.
    if (_currentPrice < 1) _currentPrice == 1;
    if (_currentPrice > 1000) _currentPrice == 1000;

    _currentPrice = newPrice;
  }

  double get currentPrice => _currentPrice;

  /// Set the current price of the stock, but rounding to 2 decimal places.
  void setCurrentPrice(double price) {
    _currentPrice = _round(price);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AvailableStock &&
          runtimeType == other.runtimeType &&
          symbol == other.symbol &&
          name == other.name &&
          _currentPrice == other._currentPrice;

  @override
  int get hashCode => symbol.hashCode ^ name.hashCode ^ _currentPrice.hashCode;
}

class AvailableStocks {
  List<AvailableStock> stocks;

  AvailableStocks({
    required this.stocks,
  });

  AvailableStock findBySymbol(String symbol) {
    AvailableStock? stock = stocks.firstWhereOrNull((s) => s.symbol == symbol);
    if (stock == null) throw Exception('Stock not found: $symbol');
    return stock;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AvailableStocks && runtimeType == other.runtimeType && stocks == other.stocks;

  @override
  int get hashCode => stocks.hashCode;
}

class AppState {
  Portfolio portfolio;
  AvailableStocks availableStocks;

  static AppState initialState() => AppState(
        portfolio: Portfolio(
          stocks: [],
          cashBalance: CashBalance(0),
        ),
        availableStocks: AvailableStocks(stocks: [
          AvailableStock('IBM', name: 'International Business Machines', currentPrice: 132.64),
          AvailableStock('APPL', name: 'Apple', currentPrice: 183.58),
          AvailableStock('GOOG', name: 'Alphabet', currentPrice: 126.63),
          AvailableStock('AMZN', name: 'Amazon', currentPrice: 125.30),
          AvailableStock('META', name: 'Meta Platforms', currentPrice: 271.39),
          AvailableStock('INTC', name: 'Intel', currentPrice: 29.86),
        ]),
      );

  AppState({
    required this.portfolio,
    required this.availableStocks,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppState && runtimeType == other.runtimeType && portfolio == other.portfolio;

  @override
  int get hashCode => portfolio.hashCode;
}

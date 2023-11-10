import 'dart:async';
import 'dart:math';

import 'package:assorted_layout_widgets/assorted_layout_widgets.dart';
import 'package:example/business_classes.dart';
import 'package:flutter/material.dart';

AppState state = AppState.initialState();

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Stocks App Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  //
  static const cashBalanceStyle = TextStyle(fontSize: 20, color: Colors.black);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Stocks App Demo'),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cashBalance(),
          _portfolio(),
          Expanded(
            child: _availableStocks(),
          ),
        ],
      ),
    );
  }

  Widget _cashBalance() {
    return Box(
      padding: const Pad(top: 16, left: 16, right: 8),
      width: double.infinity,
      color: Colors.grey[300],
      child: Row(
        children: [
          Expanded(
              child: Text('Cash Balance: ${state.portfolio.cashBalance}', style: cashBalanceStyle)),
          CircleButton(
            backgroundColor: Colors.green,
            tapColor: Colors.green[700],
            icon: const Icon(Icons.add, color: Colors.white),
            onTap: () => setState(() {
              state.portfolio.cashBalance.add(100);
            }),
          ),
          CircleButton(
            backgroundColor: Colors.red,
            tapColor: Colors.red[800],
            icon: const Icon(Icons.remove, color: Colors.white),
            onTap: () => setState(() {
              state.portfolio.cashBalance.remove(100);
            }),
          ),
        ],
      ),
    );
  }

  Widget _portfolio() {
    return Box(
      padding: const Pad(vertical: 16, horizontal: 16),
      width: double.infinity,
      color: Colors.grey[300],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.max,
        children: [
          Row(
            children: [
              const Text('Portfolio:', style: cashBalanceStyle),
              const Box(width: 8),
              if (state.portfolio.isEmpty) const Text('—', style: cashBalanceStyle),
            ],
          ),
          const Box(height: 4),
          for (var stock in state.portfolio.stocks) StockInPortfolio(stock),
        ],
      ),
    );
  }

  Widget _availableStocks() {
    return SingleChildScrollView(
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var availableStock in state.availableStocks.list)
              AvailableStockWidget(
                availableStock,
                onBuy: () => setState(() {
                  state.portfolio.buy(availableStock);
                }),
                onSell: () => setState(() {
                  state.portfolio.sell(availableStock);
                }),
              ),
          ],
        ),
      ),
    );
  }
}

class StockInPortfolio extends StatelessWidget {
  //
  static const stockStyle = TextStyle(fontSize: 16, color: Colors.black);

  final Stock stock;

  const StockInPortfolio(this.stock, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const Pad(top: 6),
        child: Text('${stock.ticker} (${stock.howManyShares} shares @ US\$ ${stock.averagePriceStr})',
            style: stockStyle),
      );
}

class AvailableStockWidget extends StatefulWidget {
  //
  static const tickerStyle = TextStyle(fontSize: 26, color: Colors.black);
  static const nameStyle = TextStyle(fontSize: 16, color: Colors.black54);

  static const priceStyle =
      TextStyle(fontSize: 23, color: Colors.blue, fontWeight: FontWeight.bold);

  static final buyStyle = ElevatedButton.styleFrom(
    backgroundColor: Colors.green,
    foregroundColor: Colors.white,
  );

  static final sellStyle = ElevatedButton.styleFrom(
    backgroundColor: Colors.red,
    foregroundColor: Colors.white,
  );

  final AvailableStock availableStock;
  final VoidCallback onBuy, onSell;

  const AvailableStockWidget(
    this.availableStock, {
    required this.onBuy,
    required this.onSell,
    super.key,
  });

  @override
  State<AvailableStockWidget> createState() => _AvailableStockWidgetState();
}

class _AvailableStockWidgetState extends State<AvailableStockWidget> {
  //
  Timer? timer;

  @override
  void initState() {
    super.initState();

    int randomIntBetween900And1100 = Random().nextInt(200) + 900;

    timer = Timer.periodic(Duration(milliseconds: randomIntBetween900And1100), (timer) {
      setState(() {
        widget.availableStock.fluctuatePrice();
      });
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const Pad(horizontal: 12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 12),
          Row(
            children: [
              Text(widget.availableStock.ticker, style: AvailableStockWidget.tickerStyle),
              const Spacer(),
              Text(widget.availableStock.currentPriceStr, style: AvailableStockWidget.priceStyle),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                  child: Text(widget.availableStock.name, style: AvailableStockWidget.nameStyle)),
              const SizedBox(width: 8),
              ElevatedButton(
                style: AvailableStockWidget.buyStyle,
                onPressed:
                    state.portfolio.hasMoneyToBuyStock(widget.availableStock) ? widget.onBuy : null,
                child: const Text('BUY'),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                style: AvailableStockWidget.sellStyle,
                onPressed: state.portfolio.hasStock(widget.availableStock) ? widget.onSell : null,
                child: const Text('SELL'),
              ),
            ],
          ),
          const Box(height: 4),
          const Divider(),
        ],
      ),
    );
  }
}

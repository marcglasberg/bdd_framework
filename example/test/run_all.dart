import 'package:bdd_framework/bdd_framework.dart';
import 'package:flutter_test/flutter_test.dart';

import 'bdd_average_price.dart' as bdd_average_price;
import 'bdd_buy_and_sell.dart' as bdd_buy_and_sell;

void main() async {
  BddReporter.set(
    // Print the result to the console.
    ConsoleReporter(),

    // Create feature files.
    FeatureFileReporter(clearAllOutputBeforeRun: true),
  );

  group('bdd_buy_and_sell.dart', bdd_buy_and_sell.main);
  group('bdd_average_price.dart', bdd_average_price.main);

  await BddReporter.reportAll();
}

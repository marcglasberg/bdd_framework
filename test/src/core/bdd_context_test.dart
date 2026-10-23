import 'package:bdd_framework/bdd_framework.dart';
import 'package:test/test.dart';

void main() {
  BddContext contextOf(BddFramework bdd, [int? exampleNumber]) => BddContext(
        BddTableValues.from(bdd.exampleRow(exampleNumber)),
        BddMultipleTableValues.from(bdd.tables()),
      );

  BddFramework stocks() => Bdd()
      .scenario('stocks')
      .given('prices')
      .table(
        'prices',
        row(val('ticker', 'AAPL'), val('price', 50)),
        row(val('ticker', 'IBM'), val('price', 30)),
      )
      .when('the user buys')
      .table('order', row(val('ticker', 'IBM'), val('qty', 2)))
      .then('the user owns')
      .example(val('owner', 'Ana'), val('cash', 100))
      .example(val('owner', 'Bob'), val('cash', 200))
      .bdd;

  group('BddContext', () {
    test('exposes the example row and every table by name', () {
      final ctx = contextOf(stocks(), 1);

      expect(ctx.example.val('owner'), 'Bob');
      expect(ctx.example.val('cash'), 200);
      expect(ctx.table('prices').rows, hasLength(2));
      expect(ctx.table('order').row(0).val('qty'), 2);
      expect(ctx.tables.row('prices'), hasLength(2));
    });

    test('a scenario without examples has an empty example', () {
      final ctx = contextOf(Bdd().scenario('s').given('g').when('w').bdd);

      expect(ctx.example, BddTableValues({}));
      expect(ctx.example.val('anything'), isNull);
    });

    test('asking for a table that does not exist throws', () {
      final ctx = contextOf(stocks(), 0);

      expect(
        () => ctx.table('missing'),
        throwsA(isA<AssertionError>().having(
            (e) => e.message, 'message', 'There is no table named "missing".')),
      );
    });

    test('contexts with the same values are equal', () {
      final a = contextOf(stocks(), 0);
      final b = contextOf(stocks(), 0);
      final c = contextOf(stocks(), 1);

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
      expect({a, b, c}, hasLength(2));
    });
  });

  group('BddTableRows', () {
    test('row() returns the row at the index', () {
      final rows = contextOf(stocks(), 0).table('prices');

      expect(rows.row(0).val('ticker'), 'AAPL');
      expect(rows.row(1).val('ticker'), 'IBM');
    });

    test('row() throws for an index out of range', () {
      final rows = contextOf(stocks(), 0).table('prices');

      for (final index in [-1, 2]) {
        expect(
          () => rows.row(index),
          throwsA(isA<AssertionError>().having((e) => e.message, 'message',
              "You can't get table row($index), since range is 0..2.")),
        );
      }
    });

    test('rowWhere() returns the first row with the name/value pair', () {
      final rows = contextOf(stocks(), 0).table('prices');

      expect(rows.rowWhere(name: 'ticker', value: 'IBM').val('price'), 30);
      expect(rows.rowWhere(name: 'price', value: 50).val('ticker'), 'AAPL');
    });

    test('rowWhere() throws, naming the pair, when no row matches', () {
      final rows = contextOf(stocks(), 0).table('prices');

      expect(
        () => rows.rowWhere(name: 'ticker', value: 'GOOG'),
        throwsA(isA<AssertionError>().having((e) => e.message, 'message',
            'There is no table with name:"ticker" and value: "GOOG".')),
      );
    });

    test('rows returns a copy, so changing it does not change the table', () {
      final rows = contextOf(stocks(), 0).table('prices');

      rows.rows.clear();

      expect(rows.rows, hasLength(2));
    });

    test('toString lists the rows', () {
      final rows = contextOf(stocks(), 0).table('order');

      expect(rows.toString(), 'BddTableRows{[{ticker: IBM, qty: 2}]}');
    });

    test('tables with the same rows are equal', () {
      final a = contextOf(stocks(), 0).table('prices');
      final b = contextOf(stocks(), 0).table('prices');
      final c = contextOf(stocks(), 0).table('order');

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
    });
  });

  group('BddMultipleTableValues', () {
    test('toString lists every table', () {
      final tables = contextOf(stocks(), 0).tables;

      expect(
        tables.toString(),
        '{prices: [{ticker: AAPL, price: 50}, {ticker: IBM, price: 30}], '
        'order: [{ticker: IBM, qty: 2}]}',
      );
    });

    test('the same tables are equal', () {
      final a = contextOf(stocks(), 0).tables;
      final b = contextOf(stocks(), 0).tables;
      final c = BddMultipleTableValues({});

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
    });
  });

  group('BddTableValues', () {
    test('val() returns null for a column that does not exist', () {
      final values = BddTableValues.from([val('a', 1)]);

      expect(values.val('a'), 1);
      expect(values.val('b'), isNull);
    });

    test('from() accepts null', () {
      expect(BddTableValues.from(null), BddTableValues({}));
    });

    test('toString shows the values', () {
      expect(BddTableValues.from([val('a', 1), val('b', 'x')]).toString(),
          '{a: 1, b: x}');
    });

    test('the same values are equal', () {
      final a = BddTableValues.from([val('a', 1), val('b', 'x')]);
      final b = BddTableValues.from([val('a', 1), val('b', 'x')]);
      final c = BddTableValues.from([val('a', 2)]);

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
    });
  });
}

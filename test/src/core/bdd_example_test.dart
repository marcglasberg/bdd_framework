import 'package:bdd_framework/bdd_framework.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BddExample', () {
    group('toString()', () {
      group('rendering examples', () {
        test('should render the Examples keyword and table rows correctly', () {
          final example = Bdd(BddFeature('Example Feature'))
              .scenario('Example Scenario')
              .given('a condition')
              .when('an action')
              .then('an outcome')
              .example(
                val('number', 123),
                val('password', 'abc'),
              )
              .example(
                val('number', 456),
                val('password', 'xyz'),
              );

          final output = example.toString(const BddConfig());
          expect(
            output,
            [
              '    Examples: ',
              '      | number | password |',
              '      | 123    | abc      |',
              '      | 456    | xyz      |',
            ].join('\n'),
          );
        });
      });

      group('with default config', () {
        test('should render correctly', () {
          final example = Bdd(BddFeature('Example Feature'))
              .scenario('Example Scenario')
              .given('a condition')
              .when('an action')
              .then('an outcome')
              .example(
                val('number', 123),
                val('password', 'abc'),
              );

          final output = example.toString(const BddConfig());
          expect(
            output,
            [
              '    Examples: ',
              '      | number | password |',
              '      | 123    | abc      |',
            ].join('\n'),
          );
        });
      });

      group('with BddRunner config', () {
        test('should apply bold/italic markers', () {
          final example = Bdd(BddFeature('Example Feature'))
              .scenario('Example Scenario')
              .given('a condition')
              .when('an action')
              .then('an outcome')
              .example(val('number', 123));

          final output = example.toString(BddRunner.config);
          const bi = BddRunner.boldItalic;
          const bo = BddRunner.boldItalicOff;
          expect(
            output,
            [
              '    ${bi}Examples:$bo ',
              '      | number |',
              '      | 123    |',
            ].join('\n'),
          );
        });
      });
    });

    group('rows', () {
      test('should append rows when chaining multiple example calls', () {
        final bdd = Bdd(BddFeature('Example Feature'))
            .scenario('Example Scenario')
            .given('a condition')
            .when('an action')
            .then('an outcome')
            .example(
              val('number', 123),
              val('password', 'abc'),
            )
            .example(
              val('number', 456),
              val('password', 'xyz'),
            );

        expect(bdd.rows, hasLength(2));
        expect(
          {for (final v in bdd.rows[0]) v.name: v.value},
          {'number': 123, 'password': 'abc'},
        );
        expect(
          {for (final v in bdd.rows[1]) v.name: v.value},
          {'number': 456, 'password': 'xyz'},
        );
      });
    });

    group('DSL Integration', () {
      test('should allow examples after then followed by and', () {
        final reporter = _TestBddReporter(const BddConfig());
        final seenExamples = <BddTableValues>[];

        Bdd(BddFeature('Example Feature'))
            .scenario('Example Scenario')
            .given('a condition')
            .when('an action')
            .then('an outcome')
            .and('another outcome')
            .example(
              val('number', 123),
              val('password', 'abc'),
            )
            .example(
              val('number', 456),
              val('password', 'xyz'),
            )
            .testRun((ctx) {
              seenExamples.add(ctx.example);
            }, reporter);

        expect(seenExamples, [
          BddTableValues({'number': 123, 'password': 'abc'}),
          BddTableValues({'number': 456, 'password': 'xyz'}),
        ]);
      });

      test('should allow examples after then followed by but', () {
        final reporter = _TestBddReporter(const BddConfig());
        final seenExamples = <BddTableValues>[];

        Bdd(BddFeature('Example Feature'))
            .scenario('Example Scenario')
            .given('a condition')
            .when('an action')
            .then('an outcome')
            .but('not a different outcome type')
            .example(
              val('number', 123),
              val('password', 'abc'),
            )
            .example(
              val('number', 456),
              val('password', 'xyz'),
            )
            .testRun((ctx) {
              seenExamples.add(ctx.example);
            }, reporter);

        expect(seenExamples, [
          BddTableValues({'number': 123, 'password': 'abc'}),
          BddTableValues({'number': 456, 'password': 'xyz'}),
        ]);
      });

      test('should allow examples after then code followed by and', () {
        final reporter = _TestBddReporter(const BddConfig());
        final seenExamples = <BddTableValues>[];

        Bdd(BddFeature('Example Feature'))
            .scenario('Example Scenario')
            .given('a condition')
            .when('an action')
            .then('an outcome')
            .code((_) {})
            .and('another outcome')
            .example(
              val('number', 123),
              val('password', 'abc'),
            )
            .example(
              val('number', 456),
              val('password', 'xyz'),
            )
            .testRun((ctx) {
              seenExamples.add(ctx.example);
            }, reporter);

        expect(seenExamples, [
          BddTableValues({'number': 123, 'password': 'abc'}),
          BddTableValues({'number': 456, 'password': 'xyz'}),
        ]);
      });

      test('should allow examples after then code followed by but', () {
        final reporter = _TestBddReporter(const BddConfig());
        final seenExamples = <BddTableValues>[];

        Bdd(BddFeature('Example Feature'))
            .scenario('Example Scenario')
            .given('a condition')
            .when('an action')
            .then('an outcome')
            .code((_) {})
            .but('not a different outcome type')
            .example(
              val('number', 123),
              val('password', 'abc'),
            )
            .example(
              val('number', 456),
              val('password', 'xyz'),
            )
            .testRun((ctx) {
              seenExamples.add(ctx.example);
            }, reporter);

        expect(seenExamples, [
          BddTableValues({'number': 123, 'password': 'abc'}),
          BddTableValues({'number': 456, 'password': 'xyz'}),
        ]);
      });
    });
  });
}

class _TestBddReporter extends BddReporter {
  _TestBddReporter(this.config);

  final BddConfig config;

  @override
  Future<void> report() async {}
}
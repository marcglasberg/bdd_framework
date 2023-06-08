import 'package:bdd_framework/bdd_framework.dart';
import "package:flutter_test/flutter_test.dart";

void main() {
  

  var defaultBdd = () => Bdd(BddFeature('F', description: '123\n456'))
      .scenario('a')
      .given('b')
      .table(
        'my-table',
        row(
          val('number', 5182850),
          val('password', 'xyz'),
          val('name', 'Mark'),
        ),
      )
      .when('c')
      .and('c2')
      .then('d')
      .example(
        val('number', 5182850),
        val('password', 'xyz'),
        val('name', 'Mark'),
      )
      //
      .example(
        val('number', 190),
        val('password', 'abcd'),
        val('name', 'Zaher'),
      );

  

  test('Running code, once.', () {
    //
    var reporter = _TestBddReporter(const BddConfig());

    var a = 0;
    var b = 0;
    var c = 0;
    var d = 0;
    var e = 0;
    var f = 0;
    var g = 0;

    var feature = BddFeature('F');

    Bdd(feature)
        .scenario('1')
        .given('2')
        .code((_) => a++)
        .code((_) => b++)
        .when('3')
        .code((_) => c++)
        .code((_) => d++)
        .then('4')
        .code((_) => e++)
        .code((_) => f++)
        .testRun((_) => g++, reporter);

    expect(a, 1);
    expect(b, 1);
    expect(c, 1);
    expect(d, 1);
    expect(e, 1);
    expect(f, 1);
    expect(g, 1);

    expect(reporter.features.length, 1);
    expect(reporter.features.first, feature);
    expect(reporter.features.first.testResults.length, 1);
    expect(reporter.features.first.testResults.first.passed, [true]);
  });

  

  test('Running code, with examples.', () {
    //
    var reporter = _TestBddReporter(const BddConfig());

    var a = 0;
    var b = 0;
    var c = 0;
    var d = 0;
    var e = 0;
    var f = 0;
    var g = 0;

    List _vals1 = [];
    List _vals2 = [];
    List _vals3 = [];
    List _vals4 = [];
    List _vals5 = [];
    List _vals6 = [];
    List _vals7 = [];

    Bdd(BddFeature('F'))
        .scenario('1')
        .given('2')
        .code((ctx) {
          _vals1.add(ctx.example);
          a++;
        })
        .code((ctx) {
          _vals2.add(ctx.example);
          b++;
        })
        .when('3')
        .code((ctx) {
          _vals3.add(ctx.example);
          c++;
        })
        .code((ctx) {
          _vals4.add(ctx.example);
          d++;
        })
        .then('4')
        .code((ctx) {
          _vals5.add(ctx.example);
          e++;
        })
        .code((ctx) {
          _vals6.add(ctx.example);
          f++;
        })
        .example(
          val('number', 123),
          val('password', 'abc'),
          val('name', 'Mark'),
        )
        .example(
          val('number', 456),
          val('password', 'xyz'),
          val('name', 'Zaher'),
        )
        .example(
          val('number', 789),
          val('password', 'mno'),
          val('name', 'Eduardo'),
        )
        .testRun((ctx) {
          _vals7.add(ctx.example);
          g++;
          expect(g, 2); // The first and third examples will fail.
        }, reporter);

    expect(a, 3);
    expect(b, 3);
    expect(c, 3);
    expect(d, 3);
    expect(e, 3);
    expect(f, 3);
    expect(g, 3);

    var expected = [
      BddTableValues({'number': 123, 'password': 'abc', 'name': 'Mark'}),
      BddTableValues({'number': 456, 'password': 'xyz', 'name': 'Zaher'}),
      BddTableValues({'number': 789, 'password': 'mno', 'name': 'Eduardo'}),
    ];

    expect(_vals1, expected);
    expect(_vals2, expected);
    expect(_vals3, expected);
    expect(_vals4, expected);
    expect(_vals5, expected);
    expect(_vals6, expected);
    expect(_vals7, expected);

    expect(reporter.features.length, 1);
    expect(reporter.features.first.testResults.length, 1);
    expect(reporter.features.first.testResults.first.passed, [false, true, false]);
  });

  

  test('Getting table values.', () {
    //
    var reporter = _TestBddReporter(const BddConfig());

    List<BddTableRows> result = [];

    Bdd(BddFeature('F'))
        .scenario('1')
        .given('2')
        .table(
          'my-table',
          row(
            val('number', 123),
            val('password', 'abc'),
            val('name', 'Mark'),
          ),
          row(
            val('number', 456),
            val('password', 'xyz'),
            val('name', 'Zaher'),
          ),
          row(
            val('number', 789),
            val('password', 'mno'),
            val('name', 'Eduardo'),
          ),
        )
        .and('3')
        .table(
          'another-table',
          row(
            val('number', 111),
            val('password', 'abc'),
            val('name', 'John'),
          ),
          row(
            val('number', 222),
            val('password', 'xyz'),
            val('name', 'David'),
          ),
          row(
            val('number', 333),
            val('password', 'mno'),
            val('name', 'Brad'),
          ),
        )
        .when('4')
        .table(
          'yet-another-table',
          row(
            val('number', 444),
            val('password', 'abc'),
            val('name', 'Mary'),
          ),
          row(
            val('number', 555),
            val('password', 'xyz'),
            val('name', 'Joan'),
          ),
          row(
            val('number', 666),
            val('password', 'mno'),
            val('name', 'Lucy'),
          ),
        )
        .then('5')
        .table(
          'and-yet-another-table',
          row(
            val('number', 777),
            val('password', 'abc'),
            val('name', 'Kelly'),
          ),
          row(
            val('number', 888),
            val('password', 'xyz'),
            val('name', 'Alba'),
          ),
          row(
            val('number', 999),
            val('password', 'mno'),
            val('name', 'Laura'),
          ),
        )
        .testRun((ctx) {
      result.add(ctx.table('my-table'));
      result.add(ctx.table('another-table'));
      result.add(ctx.table('yet-another-table'));
      result.add(ctx.table('and-yet-another-table'));
    }, reporter);

    var expected = [
      BddTableRows([
        BddTableValues({'number': 123, 'password': 'abc', 'name': 'Mark'}),
        BddTableValues({'number': 456, 'password': 'xyz', 'name': 'Zaher'}),
        BddTableValues({'number': 789, 'password': 'mno', 'name': 'Eduardo'}),
      ]),
      BddTableRows([
        BddTableValues({'number': 111, 'password': 'abc', 'name': 'John'}),
        BddTableValues({'number': 222, 'password': 'xyz', 'name': 'David'}),
        BddTableValues({'number': 333, 'password': 'mno', 'name': 'Brad'}),
      ]),
      BddTableRows([
        BddTableValues({'number': 444, 'password': 'abc', 'name': 'Mary'}),
        BddTableValues({'number': 555, 'password': 'xyz', 'name': 'Joan'}),
        BddTableValues({'number': 666, 'password': 'mno', 'name': 'Lucy'}),
      ]),
      BddTableRows([
        BddTableValues({'number': 777, 'password': 'abc', 'name': 'Kelly'}),
        BddTableValues({'number': 888, 'password': 'xyz', 'name': 'Alba'}),
        BddTableValues({'number': 999, 'password': 'mno', 'name': 'Laura'}),
      ]),
    ];

    expect(result, expected);

    expect(result[0].row(1).val('number'), 456);
    expect(result[0].row(1).val('xyz'), isNull);

    expect(() => result[0].row(10).val('xyz'), throwsAssertionError);
  });

  

  test('If two features have the same title, they are the same feature.', () {
    //
    var reporter = _TestBddReporter(const BddConfig());

    var feature1 = BddFeature('My Feature');
    var feature2 = BddFeature('My Feature');
    var feature3 = BddFeature('Another Feature');

    var bdd1 =
        Bdd(feature1).scenario('a').given('b').when('c').then('d').testRun((_) => null, reporter);

    var bdd2 =
        Bdd(feature2).scenario('x').given('y').when('z').then('k').testRun((_) => null, reporter);

    var bdd3 =
        Bdd(feature3).scenario('l').given('m').when('n').then('o').testRun((_) => null, reporter);

    reporter.report();

    expect(reporter.features.length, 2);
    expect(reporter.features.first.bdds, [bdd1, bdd2]);
    expect(reporter.features.last.bdds, [bdd3]);
  });

  

  test('Basic report formatting.', () {
    //
    const bddConfig = BddConfig(
      indent: 2,
      rightAlignKeywords: false,
      padChar: '.',
    );

    var reporter = _TestBddReporter(bddConfig);
    defaultBdd().testRun((_) => null, reporter);
    reporter.report();

    expect(
        reporter.toString(),
        'Feature: F\n'
        '..123\n'
        '..456\n'
        '..Scenario Outline: a\n'
        '....Given b\n'
        '......| number  | password | name |\n'
        '......| 5182850 | xyz      | Mark |\n'
        '....When c\n'
        '....And c2\n'
        '....Then d\n'
        '....Examples: \n'
        '......| number  | password | name  |\n'
        '......| 5182850 | xyz      | Mark  |\n'
        '......| 190     | abcd     | Zaher |\n');
  });

  

  test('Configuring the reporter.', () {
    //
    const bddConfig = BddConfig(
      indent: 2,
      rightAlignKeywords: false,
      padChar: '.',
      endOfLineChar: '<br>\n',
      tableDivider: '<b>|</b>',
    );

    var reporter = _TestBddReporter(bddConfig);
    defaultBdd().testRun((_) => null, reporter);
    reporter.report();

    expect(
        reporter.toString(),
        'Feature: F<br>\n'
        '..123<br>\n'
        '..456<br>\n'
        '..Scenario Outline: a<br>\n'
        '....Given b<br>\n'
        '......<b>|</b> number  <b>|</b> password <b>|</b> name <b>|</b><br>\n'
        '......<b>|</b> 5182850 <b>|</b> xyz      <b>|</b> Mark <b>|</b><br>\n'
        '....When c<br>\n'
        '....And c2<br>\n'
        '....Then d<br>\n'
        '....Examples: <br>\n'
        '......<b>|</b> number  <b>|</b> password <b>|</b> name  <b>|</b><br>\n'
        '......<b>|</b> 5182850 <b>|</b> xyz      <b>|</b> Mark  <b>|</b><br>\n'
        '......<b>|</b> 190     <b>|</b> abcd     <b>|</b> Zaher <b>|</b><br>\n');
  });

  

  test('Right align keywords.', () {
    //
    const bddConfig = BddConfig(
      indent: 2,
      rightAlignKeywords: true,
      padChar: '.',
      space: '_',
    );

    var reporter = _TestBddReporter(bddConfig);
    defaultBdd().testRun((_) => null, reporter);
    reporter.report();

    expect(
        reporter.toString(),
        'Feature: F\n'
        '..123\n'
        '..456\n'
        '..Scenario Outline: a\n'
        '....Given b\n'
        '..........|_number__|_password_|_name_|\n'
        '..........|_5182850_|_xyz______|_Mark_|\n'
        '.....When c\n' // Has extra padChars here to right align.
        '......And c2\n' // Has extra padChars here to right align.
        '.....Then d\n' // Has extra padChars here to right align.
        '....Examples: \n'
        '..........|_number__|_password_|_name__|\n'
        '..........|_5182850_|_xyz______|_Mark__|\n'
        '..........|_190_____|_abcd_____|_Zaher_|\n');
  });

  

  test('Test formatters.', () {
    //
    const bddConfig = BddConfig(
      indent: 2,
      rightAlignKeywords: true,
      padChar: '',
      space: '',
      transformDescribe: _transformDescribe,
    );

    var bdd = Bdd(BddFeature('F'))
        .scenario('1')
        .given('2')
        .table(
          'my-table',
          row(
            val('a', _TestClass1()),
            val('b', _TestClass2()),
            val('c', _TestClass3()),
            val('d', _TestClass4()),
          ),
        )
        .when('3')
        .then('4')
        .example(
          val('a', _TestClass1()),
          val('b', _TestClass2()),
          val('c', _TestClass3()),
          val('d', _TestClass4()),
        );

    var reporter = _TestBddReporter(bddConfig);
    bdd.testRun((_) => null, reporter);
    reporter.report();

    expect(
        reporter.toString(),
        'Feature: F\n'
        'Scenario Outline: 1\n'
        'Given 2\n'
        '|a|b|c|d|\n'
        '|123|by transformDescribe|by BddDescribe|by describe method|\n'
        'When 3\n'
        'Then 4\n'
        'Examples: \n'
        '|a|b|c|d|\n'
        '|123|by transformDescribe|by BddDescribe|by describe method|\n'
        '');
  });

  

  test('Keywords, Prefixes and Suffixes.', () {
    //
    const bddConfig = BddConfig(
      indent: 1,
      padChar: '_',
      space: '.',
      keywords: const BddKeywords(
        feature: 'F',
        scenario: 'S',
        scenarioOutline: 'SO',
        given: 'G',
        when: 'W',
        then: 'T',
        and: 'A',
        but: 'B',
        comment: 'C',
        examples: 'E',
        table: 'L',
      ),
      prefix: const BddKeywords(
        feature: '[pF]',
        scenario: '[pS]',
        scenarioOutline: '[pSO]',
        given: '[pG]',
        when: '[pW]',
        then: '[pT]',
        and: '[pA]',
        but: '[pB]',
        comment: '[pC]',
        examples: '[pE]',
        table: '[pL]',
      ),
      suffix: const BddKeywords(
        feature: '[sF]',
        scenario: '[sS]',
        scenarioOutline: '[sSO]',
        given: '[sG]',
        when: '[sW]',
        then: '[sT]',
        and: '[sA]',
        but: '[sB]',
        comment: '[sC]',
        examples: '[sE]',
        table: '[sL]',
      ),
      keywordPrefix: const BddKeywords(
        feature: '[pkF]',
        scenario: '[pkS]',
        scenarioOutline: '[pkSO]',
        given: '[pkG]',
        when: '[pkW]',
        then: '[pkT]',
        and: '[pkA]',
        but: '[pkB]',
        comment: '[pkC]',
        examples: '[pkE]',
        table: '[pkL]',
      ),
      keywordSuffix: const BddKeywords(
        feature: '[skF]',
        scenario: '[skS]',
        scenarioOutline: '[skSO]',
        given: '[skG]',
        when: '[skW]',
        then: '[skT]',
        and: '[skA]',
        but: '[skB]',
        comment: '[skC]',
        examples: '[skE]',
        table: '[skL]',
      ),
    );

    var bdd = Bdd(BddFeature('1'))
        .scenario('2')
        .given('3')
        .table(
          'my-table',
          row(
            val('a', 'b'),
          ),
        )
        .when('4')
        .then('5')
        .note('6')
        .example(
          val('x', 'y'),
        );

    var reporter = _TestBddReporter(bddConfig);
    bdd.testRun((_) => null, reporter);
    reporter.report();

    expect(
        reporter.toString(),
        '[pkF]F[skF] [pF]1[sF]\n'
        '[pkSO]_SO[skSO] [pSO]2[sSO]\n'
        '[pkG]__G[skG] [pG]3[sG]\n'
        '[pkL]L[skL][pL]___|.a.|\n'
        '___|.b.|[sL]\n'
        '[pkW]__W[skW] [pW]4[sW]\n'
        '[pkT]__T[skT] [pT]5[sT]\n'
        '[pkC]__C[skC] [pC]6[sC]\n'
        '[pkE]__E[skE] [pE]\n'
        '___|.x.|\n'
        '___|.y.|[sE]\n'
        '');
  });

  

  test('Normalize filename.', () {
    //
    var reporter = _TestBddReporter(const BddConfig());

    expect(reporter.normalizeFileName("abfkzABFKZ0123"), "abfkzabfkz0123");
    expect(reporter.normalizeFileName("A'\"#%:/ b<>\}{} c\$!@?= d+`^/: "), "a_b_c_d");
    expect(reporter.normalizeFileName("a b  C-D_e.fgh"), "a_b__c-d_efgh");
    expect(reporter.normalizeFileName("A&B#C^D+E/F\\G\$"), "abcdefg");
  });

  
}



class _TestBddReporter extends BddReporter {
  //
  _TestBddReporter(this.config);

  final List<String> _reports = [];

  final BddConfig config;

  @override
  String toString() => _reports.join();

  @override
  Future<void> report() async {
    for (BddFeature feature in features) {
      var featureStr = feature.toString(config);
      _reports.add(featureStr);

      for (TestResult test in feature.testResults) {
        var testStr = test.toString(config);
        _reports.add(testStr);
      }
    }
  }
}



class _TestClass1 {
  @override
  String toString() => '123';
}

class _TestClass2 {
  @override
  String toString() => '456';
}

class _TestClass3 implements BddDescribe {
  @override
  String toString() => '789';

  @override
  Object? describe() => 'by BddDescribe';
}

class _TestClass4 implements BddDescribe {
  @override
  String toString() => '789';

  @override
  Object? describe() => 'by describe method';
}

Object? _transformDescribe(Object? obj) => obj is _TestClass2 ? 'by transformDescribe' : null;



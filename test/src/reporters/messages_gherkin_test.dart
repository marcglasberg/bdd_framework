import 'package:bdd_framework/src/reporters/messages_gherkin.dart';
import 'package:cucumber_gherkin/cucumber_gherkin.dart' as gherkin;
import 'package:cucumber_messages/cucumber_messages.dart' as messages;
import 'package:test/test.dart';

List<messages.Envelope> _messages(String source) {
  var nextId = 0;
  return safeGherkinMessages(source, 'test.feature', () => '${nextId++}');
}

List<messages.Pickle> _pickles(String source) => _messages(
  source,
).map((envelope) => envelope.pickle).whereType<messages.Pickle>().toList();

void main() {
  for (final width in [4, 6, 8]) {
    test('a $width-column replacement chain stays literal', () {
      final names = List.generate(width, (i) => 'c$i');
      final values = List.generate(
        width,
        (i) => i == width - 1
            ? 'end'
            : '<c${i + 1}><c${i + 1}><c${i + 1}><c${i + 1}>',
      );
      final source =
          'Feature: chains\n'
          '  Scenario Outline: case <c0>\n'
          '    Given value <c0>\n'
          '    Then table\n'
          '      | <c0> |\n'
          '    Examples:\n'
          '      | ${names.join(' | ')} |\n'
          '      | ${values.join(' | ')} |\n';
      final pickle = _pickles(source).single;
      expect(pickle.name, 'case <c1><c1><c1><c1>');
      expect(pickle.steps.first.text, 'value <c1><c1><c1><c1>');
      expect(
        pickle.steps.last.argument!.dataTable!.rows.single.cells.single.value,
        '<c1><c1><c1><c1>',
      );
      expect(_messages(source).first.source!.data, source);
    });
  }

  test(
    'literal tokens support special names and longest overlapping names',
    () {
      const source = r'''Feature: literal tokens
  Scenario Outline: <a>tail> <a> <a.b+$> <unknown>
    Given <a>tail> <a> <a.b+$> <unknown>
    Examples:
      | a | a>tail | a.b+$ |
      | short | long | $1\literal |
''';
      final pickle = _pickles(source).single;
      expect(pickle.name, r'long short $1\literal <unknown>');
      expect(pickle.steps.single.text, r'long short $1\literal <unknown>');
    },
  );

  test('self references and Unicode replacements are not rescanned', () {
    const source = '''Feature: literal values
  Scenario Outline: <x> <y>
    Given <x> <y>
    Examples:
      | x | y |
      | <x><x> | café 😀 <x> |
''';
    expect(_pickles(source).single.steps.single.text, '<x><x> café 😀 <x>');
  });

  test('DocString content and media type use the same single pass', () {
    const source = '''Feature: documents
  Scenario Outline: <a>
    Given document
      """<a>
      payload <a> <b>
      """
    Examples:
      | a | b |
      | <b> | json |
''';
    final doc = _pickles(source).single.steps.single.argument!.docString!;
    expect(doc.mediaType, '<b>');
    expect(doc.content, 'payload <b> json');
  });

  test('normal Gherkin preserves the upstream envelopes and AST mappings', () {
    const source = '''@feature
Feature: parity
  Background:
    Given shared context
  @plain
  Scenario: ordinary
    And another context
    When action
    Then outcome
  @rule
  Rule: nested
    Background:
      Given rule context
    @scenario
    Scenario Outline: value <n>
      And input <n>
      When action
        | value | <n> |
      Then document
        """text/plain
        result <n>
        """
      @examples
      Examples:
        | n |
        | first |
        | second |
''';
    var nextId = 0;
    final expected = gherkin.generateMessages(
      source,
      'test.feature',
      gherkin.GherkinOptions(idGenerator: () => '${nextId++}'),
    );
    final actual = _messages(source);
    expect(
      actual.map((envelope) => envelope.toJson()).toList(),
      expected.map((envelope) => envelope.toJson()).toList(),
    );
    final pickles = actual
        .map((e) => e.pickle)
        .whereType<messages.Pickle>()
        .toList();
    expect(pickles.length, 3);
    expect(pickles.last.tags.map((tag) => tag.name), [
      '@feature',
      '@rule',
      '@scenario',
      '@examples',
    ]);
    expect(pickles.last.astNodeIds.length, 2);
    expect(pickles.last.steps[0].astNodeIds.length, 1);
    expect(pickles.last.steps[2].astNodeIds.last, pickles.last.astNodeIds.last);
    expect(pickles.last.steps[2].type, messages.PickleStepType.context);
  });

  test('duplicate example headers are rejected', () {
    const source = '''Feature: duplicate
  Scenario Outline: <x>
    Given <x>
    Examples:
      | x | x |
      | first | second |
''';
    expect(
      () => _messages(source),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('Duplicate'),
        ),
      ),
    );
  });

  test('invalid example row widths remain an explicit parser error', () {
    const source = '''Feature: width
  Scenario Outline: <x>
    Given <x>
    Examples:
      | x | y |
      | only-one |
''';
    final output = _messages(source);
    expect(output.any((envelope) => envelope.parseError != null), isTrue);
    expect(output.any((envelope) => envelope.pickle != null), isFalse);
  });

  test('oversized source is rejected before parsing or generating IDs', () {
    final source = List.filled(1024 * 1024 + 1, 'x').join();
    var generatedIds = 0;
    expect(
      () => safeGherkinMessages(source, 'test.feature', () {
        generatedIds++;
        return '$generatedIds';
      }),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('source'),
        ),
      ),
    );
    expect(generatedIds, 0);
  });

  test(
    'wide Examples headers are rejected before constructing the matcher',
    () {
      final names = List.generate(257, (index) => 'column$index');
      final values = List.filled(257, 'value');
      final source =
          'Feature: wide table\n'
          '  Scenario Outline: bounded\n'
          '    Given <column0>\n'
          '    Examples:\n'
          '      | ${names.join(' | ')} |\n'
          '      | ${values.join(' | ')} |\n';
      expect(
        () => _messages(source),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('256 column'),
          ),
        ),
      );
    },
  );

  test('cumulative substituted text is bounded before append', () {
    final placeholders = List.filled(32, '<x>').join();
    final value = List.filled(600000, 'x').join();
    final source =
        'Feature: expanded size\n'
        '  Scenario Outline: bounded\n'
        '    Given $placeholders\n'
        '    Examples:\n'
        '      | x |\n'
        '      | $value |\n';
    expect(source.length, lessThan(1024 * 1024));
    expect(
      () => _messages(source),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('16 Mi'),
        ),
      ),
    );
  });

  test('duplicated literal text also counts towards the output budget', () {
    final text = List.filled(60000, 'x').join();
    final rows = List.filled(300, '      | value |\n').join();
    final source =
        'Feature: repeated literal\n'
        '  Scenario Outline: bounded\n'
        '    Given $text\n'
        '    Examples:\n'
        '      | x |\n$rows';
    expect(
      () => _messages(source),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('16 Mi'),
        ),
      ),
    );
  });

  test('case and step products stop at the generated item budget', () {
    final steps = List.filled(334, '    Given value\n').join();
    final rows = List.filled(300, '      | value |\n').join();
    final source =
        'Feature: bounded product\n'
        '  Scenario Outline: bounded\n$steps'
        '    Examples:\n'
        '      | x |\n$rows';
    expect(
      () => _messages(source),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('100000'),
        ),
      ),
    );
  });

  test('separately valid features share the generated item budget', () {
    final steps = List.filled(334, '    Given value\n').join();
    final rows = List.filled(150, '      | value |\n').join();
    final source =
        'Feature: shared product\n'
        '  Scenario Outline: bounded\n$steps'
        '    Examples:\n'
        '      | x |\n$rows';
    // Either feature fits on its own (150 cases + 50100 steps).
    expect(_messages(source).length, 152);
    final budget = GherkinMessageBudget();
    var nextId = 0;
    List<messages.Envelope> compile() => safeGherkinMessages(
      source,
      'shared.feature',
      () => '${nextId++}',
      budget: budget,
    );
    expect(compile().length, 152);
    expect(
      compile,
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('100000'),
        ),
      ),
    );
  });

  test(
    'shared budget accounts for source descriptions without any pickles',
    () {
      final source =
          'Feature: description\n  ${List.filled(1000000, 'x').join()}\n';
      final budget = GherkinMessageBudget();
      for (var i = 0; i < 16; i++) {
        final output = safeGherkinMessages(
          source,
          'description.feature',
          () => 'unused',
          budget: budget,
        );
        expect(output.length, 2); // Source and AST, no generated case or step.
      }
      expect(
        () => safeGherkinMessages(
          source,
          'description.feature',
          () => 'unused',
          budget: budget,
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('16 Mi'),
          ),
        ),
      );
    },
  );
}

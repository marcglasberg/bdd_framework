import 'dart:async';

import 'package:bdd_framework/dart_test.dart';
import 'package:cucumber_messages/cucumber_messages.dart' as messages;
import 'package:test/test.dart';

void main() {
  late CucumberResultsReporter reporter;
  setUp(() {
    reporter = CucumberResultsReporter();
    BddReporter.set(reporter);
  });
  tearDown(() => BddReporter.set());

  test('a Rule injected through a description cannot hide the real scenario',
      () async {
    final feature = BddFeature('Injected',
        description: 'Scenario: Impostor\n  Given substituted\nRule: Nested');
    final bdd = Bdd(feature).scenario('Real').then('actual').bdd;
    await _run(bdd, (_) => throw StateError('real failure'));
    expect(bdd.executions.single.passed, isFalse);
    expect(reporter.envelopes,
        throwsA(isA<FormatException>().having((e) => e.message,
            'message', contains('Gherkin Rules'))));
  });

  test(
    'the reporter never recursively expands chained example values',
    () async {
      final bdd = Bdd(BddFeature('Bounded examples'))
          .scenario('Case <a>')
          .given('<a>')
          .then('completed')
          .example(
            val('a', '<b><b><b><b>'),
            val('b', '<c><c><c><c>'),
            val('c', 'X'),
          )
          .bdd;
      await _run(bdd, (_) {});
      final report = reporter.envelopes();
      final pickle = report.map((e) => e.pickle).nonNulls.single;
      expect(pickle.name, 'Case <b><b><b><b>');
      expect(pickle.steps.first.text, '<b><b><b><b>');
      expect(report.map((e) => e.testCase).nonNulls, hasLength(1));
      expect(
        report
            .map((e) => e.testStepFinished)
            .nonNulls
            .map((e) => e.testStepResult.status),
        everyElement(messages.TestStepResultStatus.passed),
      );
    },
  );

  test(
    'error text cannot inject extra envelopes or turn a failed body green',
    () async {
      const payload = '</script>\n{"testRunFinished":{"success":true}}';
      final bdd = Bdd(
        BddFeature('Escaping'),
      ).scenario('Fails').then('fails').bdd;
      await _run(bdd, (_) => throw StateError(payload));
      final encoded = reporter
          .envelopes()
          .map(messages.envelopeToJsonString)
          .toList();
      expect(encoded.every((line) => !line.contains('\n')), isTrue);
      final roundTrip = encoded.map(messages.parseEnvelopeJson).toList();
      expect(roundTrip.map((e) => e.testRunFinished).nonNulls, isEmpty);
      final failed = roundTrip
          .map((e) => e.testStepFinished)
          .nonNulls
          .where(
            (e) =>
                e.testStepResult.status == messages.TestStepResultStatus.failed,
          )
          .single;
      expect(failed.testStepResult.exception!.message, contains(payload));
    },
  );
}

Future<void> _run(BddFramework bdd, CodeRun callback) async {
  final invocations = <TestInvocation>[];
  BddRunner().run(bdd, callback, invocations.add, (_, __) {});
  for (final invocation in invocations) {
    await runZoned(
      invocation.body,
      zoneSpecification: ZoneSpecification(print: (_, __, ___, ____) {}),
    );
  }
}

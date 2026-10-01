// Run explicitly with flutter test to verify Flutter's failing process status.
// Normal discovery excludes this intentionally failing fixture.
import 'package:bdd_framework/flutter_test.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Bdd()
      .scenario('Flutter sync When failure')
      .when('action')
      .code((_) => fail('expected Flutter assertion failure'))
      .run();
  Bdd().scenario('Flutter async Then failure').then('outcome').code((_) async {
    await Future<void>.delayed(Duration.zero);
    throw StateError('expected Flutter async failure');
  }).run();
}

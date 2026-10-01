/// The runner-agnostic API of the BDD framework: the BDD DSL, contexts,
/// [BddRunner] and the reporters, but no `.run()` extension.
///
/// Import this library when writing a custom runner in a separate package
/// (for example, `bdd_framework_patrol`). To write tests, import one of the
/// runner libraries instead: `dart_test.dart`, `flutter_test.dart` or
/// `flutter_widget_test.dart`.
library;

export 'src/core.dart';
export 'src/reporter.dart';

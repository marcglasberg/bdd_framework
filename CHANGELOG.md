Sponsored by [MyText.ai](https://mytext.ai)

[![](https://raw.githubusercontent.com/marcglasberg/bdd_framework/master/example/SponsoredByMyTextAi.png)](https://mytext.ai)

## 5.2.0

* `CucumberResultsReporter()` writes the results of your BDDs (which scenarios
  and steps passed, failed or were skipped, how long they took, and the errors)
  in Cucumber's standard results format,
  [Cucumber Messages](https://github.com/cucumber/messages). Use it to create
  an HTML report of each test run with
  [Cucumber's HTML formatter](https://github.com/cucumber/html-formatter), or
  to send the results to other tools that understand Cucumber. See its
  documentation for how to use it
  ([#17](https://github.com/marcglasberg/bdd_framework/issues/17)).

* The results report is created in two steps. While the tests run, the
  reporter writes `results.ndjson.partial`. After the test command exits,
  `dart run bdd_framework:finalize_cucumber_results` combines it with the test
  runner's JSON output and exit code, and writes the final `results.ndjson`
  with the real result of the whole run. Interrupted or inconsistent runs
  produce an error instead of a report. Other reporters don't need this step.

* The report fails with an error, instead of silently leaving tests out or
  keeping an old report, when the Gherkin is invalid, steps or examples don't
  match, or the file can't be written. Output paths that are links are
  rejected, and the report is written to a temporary file and then renamed, so
  a half-written report is never left behind. Report sizes are limited. See the
  `CucumberResultsReporter` documentation for the limits, and for how to handle
  reports that contain sensitive test data.

* Each run of a BDD is now recorded, with the result, duration and error of
  each code block that ran. Reporters can read it from
  `TestResult.executions` (or `BddFramework.executions`). See `BddExecution`.

* `BddTerm.isNote` tells if a term is a note, added with `.note()`.

* Requires Dart 3.8 (Flutter 3.32), since `cucumber_gherkin` and
  `cucumber_messages` are now dependencies.

## 5.1.0

* `Bdd(feature).only` runs only that BDD while you work on it, like `test.only`
  in Jest. The other BDDs in the same test file are skipped, unless they are
  also marked with `.only`. It works with the Dart, Flutter and Flutter widget
  runners. Since it's meant to be temporary, the analyzer warns about it, as a
  reminder to remove it before committing
  ([#3](https://github.com/marcglasberg/bdd_framework/issues/3)).

## 5.0.3

* Exported feature files are now always valid Gherkin
  ([#18](https://github.com/marcglasberg/bdd_framework/issues/18),
  [#19](https://github.com/marcglasberg/bdd_framework/issues/19),
  [#20](https://github.com/marcglasberg/bdd_framework/issues/20)):
    * A `|` in a table or `Examples` cell is written as `\|`, and a line break
      as `\n`. A backslash is escaped only where Gherkin would misread it, so
      values like `C:\tmp` or `\d+` are written unchanged.
    * A line break in a step, scenario name, feature title or user story is
      written as a space, instead of starting a new scenario or step.
    * Each line of a multi-line `note()` becomes its own `#` comment.
    * A feature title with a line break no longer makes the `.feature` file
      fail to be created.
  The console output uses the same formatting, so it changes the same way.

* In widget tests (`flutter_widget_test.dart`), an error Flutter reports
  without throwing it, like a layout overflow when
  `BddFlutter.ignoreOverflow` is `false`, now fails the step where it happens.
  Previously the BDD printed `TEST PASSED!` and Flutter failed the test only
  afterwards. The steps after it don't run, and the error is shown with its
  original details. An error the test takes itself with
  `tester.takeException()` doesn't fail the step.

* `ctx.table(...).rowWhere(...)` now shows the value it looked for in its error
  message, instead of the column name twice.

* `BddContext`, `BddTableRows`, `BddMultipleTableValues` and `BddTableValues`
  with the same values are now equal and have the same `hashCode`.

* When `FeatureFileReporter` can't write a feature file, it now says which
  feature failed and why.

* Thanks to [Andrew Friedman](https://github.com/Fried-man) for the Gherkin
  conformance tests that found the export bugs.

## 5.0.2

* `FeatureFileReporter(clearAllOutputBeforeRun: true)` now deletes only the
  `.feature` files directly inside `FeatureFileReporter.dir`. Previously it
  recursively deleted the whole directory, including any other files in it.
  An empty `FeatureFileReporter.dir` now means the current directory, instead
  of the filesystem root.

## 5.0.0

* If you want to use [Patrol](https://pub.dev/packages/patrol), see the new
  [bdd_framework_patrol](https://pub.dev/packages/bdd_framework_patrol) package.
  Its code was contributed by [Kahoulam](https://github.com/Kahoulam).

* **Breaking:** `.run()` and `.code()` are now extension methods that come from
  a runner import: `package:bdd_framework/bdd_framework.dart` or
  `flutter_test.dart` (Flutter tests), `flutter_widget_test.dart` (widget tests
  with a `WidgetTester`), or `dart_test.dart` (pure Dart tests). If you import
  `bdd_framework.dart` with a `show` clause, also show `FlutterTestRun` and
  `FlutterTestCode`.

* Fix pure Dart BDD tests reporting success to `package:test` after a failed
  assertion or exception. Synchronous and asynchronous failures now fail the
  underlying test and return a failing test-process exit code.

* Restore custom-formatting and feature-collection regression coverage, and test
  execution of scenarios starting directly with When or Then.

* New `package:bdd_framework/core.dart` exposes the runner-agnostic API (no
  `.run()` extension) for runners in other packages.

## 4.0.7

* Version bump of dependencies

## 3.0.2

* Compatible with Flutter 3.13.9 version.

* Internal frames are not shown in the error stack-traces. This simplifies the reported stack-traces
  by removing lines which are not from your application code.

## 2.0.1

* Documentation, BDD tutorial and example app.

## 1.0.0

* Initial version.

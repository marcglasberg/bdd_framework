## Unreleased

* Fix pure Dart BDD tests reporting success to `package:test` after a failed
  assertion or exception. Synchronous and asynchronous failures now fail the
  underlying test and return a failing test-process exit code.
* Restore custom-formatting and feature-collection regression coverage, and test
  execution of scenarios starting directly with When or Then.

## 4.0.7

* Sponsored by [MyText.ai](https://mytext.ai)

[![](https://raw.githubusercontent.com/marcglasberg/bdd_framework/master/example/SponsoredByMyTextAi.png)](https://mytext.ai)

* Version bump of dependencies

## 3.0.2

* Compatible with Flutter 3.13.9 version.

* Internal frames are not shown in the error stack-traces. This simplifies the reported stack-traces
  by removing lines which are not from your application code.

## 2.0.1

* Documentation, BDD tutorial and example app.

## 1.0.0

* Initial version.

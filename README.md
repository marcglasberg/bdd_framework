<a href="https://pub.dartlang.org/packages/bdd_framework"><img src="https://img.shields.io/pub/v/bdd_framework.svg"></a>

# BDD Framework

> _This package is brought to you by <a href="https://www.linkedin.com/in/zhammoud/">Zaher
Hammoud</a>, and myself, <a href="https://github.com/marcglasberg">Marcelo Glasberg</a>._

This is a <a href='https://en.wikipedia.org/wiki/Behavior-driven_development'>BDD framework</a> for
Dart/Flutter:

* It lets you create BDD tests in code.
* It gives you easy to read error messages when assertions fail.
* It does not need generated code to work.
* No "glue files" are needed.
* It's "developer-centric", meaning it caters to the needs of software developers first, not product
  managers.
* Easy to use both for standalone developers and for teams.
* Will help you write a lot more BDDs, since it makes them so easy.
* Exports to Gherkin/Cucumber `.feature` files (optional).

_See https://docs.cucumber.io/gherkin/ for information on the Gherkin syntax._

## 2. How

Other BDD packages work like this:

- Product managers write BDDs into well-formed feature files.
- Developers create "glue files" for those feature files.
- Developers implement the BDDs.
- If developers find problems and missing information in the feature files, they need to let the
  managers know, wait for the files to be fixed, and then redo the glue files and implement the
  fixes in code.
- If developers notice missing BDDs, they also must ask the manager to create new feature files.

The above process is usually painful for developers, resulting in less BDDs being written.

This **BDD Framework**'s process is very different and much easier:

- Product managers write BDD drafts. Doesn't need to be well-formed feature files.
- Developers implement the BDDs in code.
- If developers find problems and missing information in the feature files, they can just fix them
  right away, in code.
- If developers notice missing BDDs, they can just add them right away, in code.
- Developers run the BDD tests and get the results. They can see both the BDD text and the results
  very well formatted in the console.
- Running the BDD tests also creates the feature files automatically.
- The feature files will then naturally get committed to the version control repo. The product
  manager can then review them to see if they are correct. This also maintains an historical record
  of feature file changes in the repo. They can even be diffed to make it clear what changed from
  version to version.

I believe this package's process is also easier on the product managers, since they don't need to
write well-formed BDDs from the start. And they can trust the developers to add detail when they
are implementing the code, which is when the details become obvious.

## 3. Creating your BDD tests

You create your BDD tests in code, not in `.feature` files. For example:

```
import 'package:bdd_framework/bdd_framework.dart';
import "package:flutter_test/flutter_test.dart";

void main() {

    var feature = BddFeature('Buying amount');
    
    Bdd(feature)
       .scenario('Buying amount for stock orders, with zero fees.')
       //
       .given('The user has 120 dollars.')
       .and('IBM bid-price is 3 dollars, ask-price is 10.')
       .and('Fees are zero.')
       //
       .when('The user opens the order.')
       //
       .then('The buying amount is 12 shares.')
       .and('It costs 120 dollars.')
       //      
       .run((ctx) async {
           
           // Given:
           setCashBalance(120);         
           setQuote(IBM, bid: 3, ask: 10);
           setFees(0);         
        
           // When:
           var buyingAmount = openOrder(IBM);
             
           // Then:
           expect(buyingAmount.shares, 12);         
           expect(buyingAmount.dollars, 120);
       });
       
    Bdd(feature)
       .scenario('Another scenario here.')
       ...   
}       
```
       
The above code would automatically generate a feature file like this:

```
Feature: Buying amount

  Scenario: Buying amount for stock orders, with zero fees.
    Given the user has 120 dollars.
    And IBM bid-price is 3 dollars, ask-price is 10.
    And fees are zero.
    When the user opens the order.
    Then the buying amount is 12 shares.
    And it costs 120 dollars.
    
  Scenario: Another scenario here.
    ...  
```
<br>

## 4. Running all BDDs at once

Create a file called `run_all.dart` and list all your bdd files.
Here, for example, we list 3 BDD files: `bdd_search_test.dart`, `bdd_activity_test.dart`
and `bdd_notifications_test.dart`

```
import 'package:bdd_framework/bdd_framework.dart';
import 'package:flutter_test/flutter_test.dart';

import '../bdd_search_test.dart' as bdd_search_test;
import '../bdd_activity_test.dart' as bdd_activity_test;
import '../bdd_notifications_test.dart' as bdd_search_test;

void main() async {
  
  /// This will print the result to the console. 
  BddReporter.set(
     ConsoleReporter(),
     FeatureFileReporter(clearAllOutputBeforeRun: true),
  );    

  group('bdd_search_test.dart', bdd_search_test.main);
  group('bdd_activity_test.dart', bdd_activity_test.main);  
  group('bdd_notifications_test', bdd_notifications_test.main);  

  await BddReporter.reportAll();
}
```

The `BddReporter.set()` method lets you add one or more "reporters" to decide where you want to see
the test results. You can create any reporters want by extending the `BddReporter` class. For
example, you could create an `HtmlReporter()` to output your tests as HTML and then add them to your
internal company's website.

The **BDD Framework** package comes out of the box with 2 reporters:

* `ConsoleReporter()` prints the results to the console. Under IntelliJ for Windows
  the output will have color. Note: Colors don't work under IntelliJ for Mac.

<p>

* `FeatureFileReporter()` writes the results into `.feature` files that contain your BDDs in
  <a href='https://en.wikipedia.org/wiki/Cucumber_(software)#Gherkin_language'>Gherkin language</a>.
    * If parameter `clearAllOutputBeforeRun` is true, all previous feature files will be deleted and
      recreated time you run the tests.
    * You can set the variable `FeatureFileReporter.dir` to choose the directory where your
      feature files will be created. The default is to save them into `./gen_features/`. If you save
      them into your Flutter project, you can then simply commit your code to add those files to
      your version control repo. This will serve as documentation for your current project version.
    * If you use Jira, you can
      install <a href='https://marketplace.atlassian.com/apps/1221264/cucumber-for-jira-bdd-natively-in-jira'>
      Cucumber for Jira</a> to show your BDDs inside of Jira. Each time you run the tests, create
      the feature files, and commit them to your repo, Cucumber for Jira will read those files and
      present them well formatted for you.

<br>

# Copyright

**This package is copyrighted and brought to you by <a href="https://www.parksidesecurities.com/">
Parkside Technologies</a>, a company which is simplifying global access to US stocks.**

This package is published here with permission.

Please, see the license page for more information.

***

*The Flutter packages I've authored:*

* <a href="https://pub.dev/packages/async_redux">async_redux</a>
* <a href="https://pub.dev/packages/provider_for_redux">provider_for_redux</a>
* <a href="https://pub.dev/packages/i18n_extension">i18n_extension</a>
* <a href="https://pub.dev/packages/align_positioned">align_positioned</a>
* <a href="https://pub.dev/packages/network_to_file_image">network_to_file_image</a>
* <a href="https://pub.dev/packages/image_pixels">image_pixels</a>
* <a href="https://pub.dev/packages/matrix4_transform">matrix4_transform</a>
* <a href="https://pub.dev/packages/back_button_interceptor">back_button_interceptor</a>
* <a href="https://pub.dev/packages/indexed_list_view">indexed_list_view</a>
* <a href="https://pub.dev/packages/animated_size_and_fade">animated_size_and_fade</a>
* <a href="https://pub.dev/packages/assorted_layout_widgets">assorted_layout_widgets</a>
* <a href="https://pub.dev/packages/weak_map">weak_map</a>
* <a href="https://pub.dev/packages/themed">themed</a>
* <a href="https://pub.dev/packages/bdd_framework">bdd_framework</a>

*My Medium Articles:*

* <a href="https://medium.com/flutter-community/https-medium-com-marcglasberg-async-redux-33ac5e27d5f6">
  Async Redux: Flutter’s non-boilerplate version of Redux</a> 
  (versions: <a href="https://medium.com/flutterando/async-redux-pt-brasil-e783ceb13c43">
  Português</a>)
* <a href="https://medium.com/flutter-community/i18n-extension-flutter-b966f4c65df9">
  i18n_extension</a> 
  (versions: <a href="https://medium.com/flutterando/qual-a-forma-f%C3%A1cil-de-traduzir-seu-app-flutter-para-outros-idiomas-ab5178cf0336">
  Português</a>)
* <a href="https://medium.com/flutter-community/flutter-the-advanced-layout-rule-even-beginners-must-know-edc9516d1a2">
  Flutter: The Advanced Layout Rule Even Beginners Must Know</a> 
  (versions: <a href="https://habr.com/ru/post/500210/">русский</a>)
* <a href="https://medium.com/flutter-community/the-new-way-to-create-themes-in-your-flutter-app-7fdfc4f3df5f">
  The New Way to create Themes in your Flutter App</a> 

*My article in the official Flutter documentation*:

* <a href="https://flutter.dev/docs/development/ui/layout/constraints">Understanding constraints</a>

<br>_Marcelo Glasberg:_<br>

<a href="https://github.com/marcglasberg">_github.com/marcglasberg_</a>
<br>
<a href="https://www.linkedin.com/in/marcglasberg/">_linkedin.com/in/marcglasberg/_</a>
<br>
<a href="https://twitter.com/glasbergmarcelo">_twitter.com/glasbergmarcelo_</a>
<br>
<a href="https://stackoverflow.com/users/3411681/marcg">_stackoverflow.com/users/3411681/marcg_</a>
<br>
<a href="https://medium.com/@marcglasberg">_medium.com/@marcglasberg_</a>
<br>

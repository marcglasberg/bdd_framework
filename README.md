<a href="https://pub.dartlang.org/packages/bdd_framework"><img src="https://img.shields.io/pub/v/bdd_framework.svg"></a>

# BDD Framework

> _This package is brought to you by <a href="https://www.linkedin.com/in/zhammoud/">Zaher
Hammoud</a>, and myself, <a href="https://github.com/marcglasberg">Marcelo Glasberg</a>._

<a href='https://en.wikipedia.org/wiki/Behavior-driven_development'>BDD framework</a> for
Dart/Flutter:

* Lets you create BDD tests in code.
* Gives you easy to read error messages when assertions fail.
* Exports to Gherkin/Cucumber `.feature` files (optional).
* Does not need generated code to work.

<br>

## 1. Creating your BDD tests

You create your BDD tests in code, not in `.feature` files. For example:

```
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
```

<br>

THE REST OF THE DOCUMENTATION IS COMING SOON!

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

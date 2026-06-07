import 'package:flutter/material.dart';

import '../common.dart';

void main() {
  // --- Widget interaction basics ---

  patrol('widget interaction smoke test', ($) async {
    await createApp($);
    await $.waitUntilVisible($(#counterText));

    expect($(#counterText).text, '0');
    await $(FloatingActionButton).tap();
    expect($(#counterText).text, '1');

    await $(#textField).enterText('Hello from patrol!');
    expect($('Hello from patrol!'), findsOneWidget);

    await $('Open scrolling screen').scrollTo().tap();
    await $.waitUntilVisible($(#topText));
    await $.scrollUntilVisible(finder: $(#bottomText));
    await $.tap($(#backButton));
    await $.scrollUntilVisible(
      finder: $(#counterText),
      scrollDirection: AxisDirection.up,
    );
  });

  patrol('counter controls and list tile taps', ($) async {
    await createApp($);
    await $.waitUntilVisible($(#counterText));
    expect($(#counterText).text, '0');

    await $(FloatingActionButton).tap();
    await $(FloatingActionButton).tap();
    expect($(#counterText).text, '2');

    await $(#tile1).scrollTo().tap();
    expect($(#counterText).text, '12');

    await $(#tile2).scrollTo().tap();
    expect($(#counterText).text, '2');
  });

  patrol('text field entry and replacement', ($) async {
    await createApp($);
    await $.waitUntilVisible($(#counterText));

    await $(#textField).enterText('first input');
    expect($('first input'), findsOneWidget);

    await $(#textField).enterText('replaced');
    expect($('replaced'), findsOneWidget);
    expect($('first input'), findsNothing);
  });

  // --- Scrolling ---

  patrol('scrolling with directions', ($) async {
    await createApp($);
    await $.waitUntilVisible($(#counterText));

    await $('Open scrolling screen').scrollTo().tap();
    await $.waitUntilVisible($(#topText));

    await $.scrollUntilVisible(finder: $(#bottomText));
    expect($('Some text at the bottom'), findsOneWidget);

    await $.scrollUntilVisible(
      finder: $(#topText),
      scrollDirection: AxisDirection.up,
    );

    await $.tap($(#backButton));
    await $.scrollUntilVisible(
      finder: $(#counterText),
      scrollDirection: AxisDirection.up,
    );
  });

  // --- Finder methods ---

  patrol('waitUntilExists vs waitUntilVisible', ($) async {
    await createApp($);

    await $(#counterText).waitUntilExists();
    expect($(#counterText).exists, isTrue);

    await $(#counterText).waitUntilVisible();
    expect($(#counterText).visible, isTrue);
  });

  patrol('which() filters widgets by predicate', ($) async {
    await createApp($);
    await $.waitUntilVisible($(#counterText));

    final addIcons = $(Icon).which<Icon>((icon) => icon.icon == Icons.add);
    expect(addIcons, findsWidgets);
  });

  patrol('finder: at, first, last, evaluate', ($) async {
    await createApp($);
    await $.waitUntilVisible($(#counterText));

    final icons = $(Icon);
    expect(icons.evaluate().length, greaterThanOrEqualTo(2));
    expect(icons.at(0), findsOneWidget);
    expect(icons.first, findsOneWidget);
    expect(icons.last, findsOneWidget);
  });

  patrol('nested finder chaining', ($) async {
    await createApp($);
    await $.waitUntilVisible($(#counterText));

    expect($(Scaffold).$(#counterText), findsOneWidget);
    expect($(Scaffold).$(FloatingActionButton), findsOneWidget);
    expect($(Scaffold).$(#textField), findsOneWidget);
  });

  patrol('exists and visible properties', ($) async {
    await createApp($);
    await $.waitUntilVisible($(#counterText));

    expect($(#counterText).exists, isTrue);
    expect($(#counterText).visible, isTrue);
    expect($(#nonExistentWidget).exists, isFalse);
  });

  patrol('text getter reflects state changes', ($) async {
    await createApp($);
    await $.waitUntilVisible($(#counterText));

    expect($(#counterText).text, '0');
    await $(FloatingActionButton).tap();
    expect($(#counterText).text, '1');
    await $(FloatingActionButton).tap();
    await $(FloatingActionButton).tap();
    expect($(#counterText).text, '3');
  });

  // --- Gestures and pump ---

  patrol('longPress gesture', ($) async {
    await createApp($);
    await $.waitUntilVisible($(#counterText));

    await $(FloatingActionButton).longPress();
    expect($(#counterText), findsOneWidget);
  });

  patrol('pumpAndSettle with custom timeout', ($) async {
    await createApp($);
    await $.waitUntilVisible($(#counterText));

    await $(FloatingActionButton).tap();
    await $.pumpAndSettle(timeout: const Duration(seconds: 5));
    expect($(#counterText).text, '1');
  });

  patrol('pump with duration', ($) async {
    await createApp($);
    await $.waitUntilVisible($(#counterText));

    await $(FloatingActionButton).tap();
    await $.pump(const Duration(milliseconds: 100));
    expect($(#counterText).text, '1');
  });

  patrol('multiple rapid taps', ($) async {
    await createApp($);
    await $.waitUntilVisible($(#counterText));

    for (var i = 0; i < 5; i++) {
      await $(FloatingActionButton).tap();
    }
    expect($(#counterText).text, '5');

    await $(#tile2).scrollTo().tap();
    expect($(#counterText).text, '-5');
  });

  // --- scrollUntilExists ---

  patrol('scrollUntilExists finds off-screen widget', ($) async {
    await createApp($);
    await $.waitUntilVisible($(#counterText));

    await $.scrollUntilExists(finder: $(#tile2));
    expect($(#tile2).exists, isTrue);
  });

  // --- enterText variations ---

  patrol('enterText with noSettle policy', ($) async {
    await createApp($);
    await $.waitUntilVisible($(#counterText));

    await $.enterText(
      $(#textField),
      'no settle text',
      settlePolicy: SettlePolicy.noSettle,
    );
    await $.pump(const Duration(milliseconds: 300));
    expect($('no settle text'), findsOneWidget);
  });

  // --- Navigation ---

  patrol('navigate to at-finder screen', ($) async {
    await createApp($);
    await $.waitUntilVisible($(#counterText));

    await $(#atFinderScreenButton).scrollTo().tap();
    await $.waitUntilVisible($(#atFinderItem).first);
    expect($(#atFinderItem).evaluate().length, greaterThan(0));
  });
}

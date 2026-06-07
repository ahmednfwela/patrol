import 'package:flutter/material.dart';

import '../common.dart';

void main() {
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

  patrol('longPress gesture on widget', ($) async {
    await createApp($);
    await $.waitUntilVisible($(#counterText));

    await $(FloatingActionButton).longPress();
    expect($(#counterText), findsOneWidget);
  });

  patrol('dragUntilVisible scrolls to target', ($) async {
    await createApp($);
    await $.waitUntilVisible($(#counterText));

    await $('Open scrolling screen').scrollTo().tap();
    await $.waitUntilVisible($(#topText));

    await $.dragUntilVisible(
      finder: $(#bottomText),
      view: $(#listViewKey),
      moveStep: const Offset(0, -100),
    );
    expect($(#bottomText), findsOneWidget);

    await $.tap($(#backButton));
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

  patrol('nested finder chaining', ($) async {
    await createApp($);
    await $.waitUntilVisible($(#counterText));

    expect($(Scaffold).$(#counterText), findsOneWidget);
    expect($(Scaffold).$(FloatingActionButton), findsOneWidget);
    expect($(Scaffold).$(#textField), findsOneWidget);
  });

  patrol('scrollTo with custom step and maxScrolls', ($) async {
    await createApp($);
    await $.waitUntilVisible($(#counterText));

    await $(#tile1).scrollTo(maxScrolls: 50, step: 200);
    expect($(#tile1), findsOneWidget);

    await $(#tile2).scrollTo(maxScrolls: 50);
    expect($(#tile2), findsOneWidget);
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

  patrol('evaluate returns widget elements', ($) async {
    await createApp($);
    await $.waitUntilVisible($(#counterText));

    final elements = $(#counterText).evaluate();
    expect(elements.length, 1);

    final allIcons = $(Icon).evaluate();
    expect(allIcons.length, greaterThanOrEqualTo(2));
  });
}

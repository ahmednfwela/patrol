import 'package:flutter/material.dart';

import '../common.dart';

void main() {
  patrol('finder methods: at, first, last, evaluate', ($) async {
    await createApp($);
    await $.waitUntilVisible($(#counterText));

    final icons = $(Icon).evaluate().toList();
    expect(icons.length, greaterThanOrEqualTo(2));

    expect($(Icon).first, findsOneWidget);
    expect($(Icon).last, findsOneWidget);
    expect($(Icon).at(0), findsOneWidget);
  });

  patrol('scrollTo and scrollUntilVisible with directions', ($) async {
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
    expect($('Some text at the top'), findsOneWidget);

    await $.tap($(#backButton));
  });

  patrol('text entry, replacement, and widget text access', ($) async {
    await createApp($);
    await $.waitUntilVisible($(#counterText));

    expect($(#counterText).text, '0');

    await $(#textField).enterText('test input');
    expect($('test input'), findsOneWidget);

    await $(#textField).enterText('replaced');
    expect($('replaced'), findsOneWidget);
    expect($('test input'), findsNothing);

    await $(FloatingActionButton).tap();
    expect($(#counterText).text, '1');
  });

  patrol('navigate to at-finder screen', ($) async {
    await createApp($);
    await $.waitUntilVisible($(#counterText));

    await $(#atFinderScreenButton).scrollTo().tap();

    await $.waitUntilVisible($(#atFinderItem).first);
    expect($(#atFinderItem).evaluate().length, greaterThan(0));
  });

  patrol('nested finder within scaffold', ($) async {
    await createApp($);
    await $.waitUntilVisible($(#counterText));

    expect($(Scaffold).$(FloatingActionButton), findsOneWidget);
    expect($(Scaffold).$(#counterText), findsOneWidget);
    expect($(Scaffold).$(#textField), findsOneWidget);
  });
}

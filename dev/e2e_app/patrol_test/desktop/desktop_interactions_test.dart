import 'package:flutter/material.dart';

import '../common.dart';

void main() {
  patrol('multiple counter increments via different controls', ($) async {
    await createApp($);
    await $.waitUntilVisible($(#counterText));
    expect($(#counterText).text, '0');

    await $(FloatingActionButton).tap();
    expect($(#counterText).text, '1');

    await $(FloatingActionButton).tap();
    await $(FloatingActionButton).tap();
    expect($(#counterText).text, '3');

    await $(#tile1).tap();
    expect($(#counterText).text, '13');

    await $(#tile2).tap();
    expect($(#counterText).text, '3');
  }, tags: ['desktop']);

  patrol('text entry and verification', ($) async {
    await createApp($);
    await $.waitUntilVisible($(#counterText));

    await $(#textField).enterText('patrol desktop test');
    expect($('patrol desktop test'), findsOneWidget);

    await $(#textField).enterText('replaced text');
    expect($('replaced text'), findsOneWidget);
    expect($('patrol desktop test'), findsNothing);
  }, tags: ['desktop']);

  patrol('navigate to scrolling screen and back', ($) async {
    await createApp($);
    await $.waitUntilVisible($(#counterText));

    await $('Open scrolling screen').scrollTo().tap();
    await $.waitUntilVisible($(#topText));
    expect($('Some text at the top'), findsOneWidget);

    await $.scrollUntilVisible(finder: $(#bottomText));
    expect($('Some text at the bottom'), findsOneWidget);

    await $.scrollUntilVisible(
      finder: $(#topText),
      scrollDirection: AxisDirection.up,
    );
    expect($('Some text at the top'), findsOneWidget);

    await $.tap($(#backButton));
    await $.waitUntilVisible($(#counterText));
  }, tags: ['desktop']);

  patrol('finder chaining with at()', ($) async {
    await createApp($);
    await $.waitUntilVisible($(#counterText));

    final textButtons = $('Open scrolling screen')
        .evaluate()
        .toList();
    expect(textButtons, isNotEmpty);
  }, tags: ['desktop']);

  patrol('waitUntilVisible succeeds for visible widget', ($) async {
    await createApp($);

    await $.waitUntilVisible($(#counterText));
    await $.waitUntilVisible($(#textField));
    await $.waitUntilVisible($(FloatingActionButton));
  }, tags: ['desktop']);
}

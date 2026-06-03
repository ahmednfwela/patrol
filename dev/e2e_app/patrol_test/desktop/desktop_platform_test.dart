import 'package:flutter/material.dart';

import '../common.dart';

void main() {
  patrol('platform.tap routes to desktop automator', ($) async {
    await createApp($);
    await $.waitUntilVisible($(#counterText));

    try {
      await $.platform.tap(
        Selector(text: 'NonExistentElement'),
        timeout: const Duration(seconds: 2),
      );
    } on Exception catch (e) {
      expect(e.toString(), isNot(contains('Unsupported')));
      expect(e.toString(), contains('ELEMENT_NOT_FOUND'));
    }
  }, tags: ['desktop']);

  patrol('desktop.doubleTap callable', ($) async {
    await createApp($);
    await $.waitUntilVisible($(#counterText));

    try {
      await $.platform.desktop.doubleTap(name: 'NonExistent');
    } on Exception catch (e) {
      expect(e.toString(), contains('ELEMENT_NOT_FOUND'));
    }
  }, tags: ['desktop']);

  patrol('platform enterText on text field', ($) async {
    await createApp($);
    await $.waitUntilVisible($(#counterText));

    await $(#textField).enterText('typed via patrol');
    expect($('typed via patrol'), findsOneWidget);
  }, tags: ['desktop']);

  patrol('platform waitUntilVisible for counter', ($) async {
    await createApp($);

    await $.waitUntilVisible($(#counterText));
    await $.waitUntilVisible($(FloatingActionButton));
    await $.waitUntilVisible($(#textField));

    expect($(#counterText).text, '0');
  }, tags: ['desktop']);

  patrol('multiple taps verify state consistency', ($) async {
    await createApp($);
    await $.waitUntilVisible($(#counterText));

    for (var i = 0; i < 5; i++) {
      await $(FloatingActionButton).tap();
    }
    expect($(#counterText).text, '5');

    await $(#tile2).scrollTo().tap();
    expect($(#counterText).text, '-5');
  }, tags: ['desktop']);
}

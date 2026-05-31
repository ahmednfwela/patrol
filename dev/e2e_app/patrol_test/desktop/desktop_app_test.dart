import 'package:flutter/material.dart';

import '../common.dart';

void main() {
  patrol('taps around on desktop', ($) async {
    await createApp($);
    await $.waitUntilVisible($(#counterText));

    expect($(#counterText).text, '0');

    await $(FloatingActionButton).tap();

    expect($(#counterText).text, '1');

    await $(#textField).enterText('Hello, Flutter!');
    expect($('Hello, Flutter!'), findsOneWidget);

    await $('Open scrolling screen').scrollTo().tap();
    await $.waitUntilVisible($(#topText));

    await $.scrollUntilVisible(finder: $(#bottomText));

    await $.tap($(#backButton));
    await $.scrollUntilVisible(
      finder: $(#counterText),
      scrollDirection: AxisDirection.up,
    );
  }, tags: ['desktop']);

  patrol('$.platform.tap routes to desktop automator', ($) async {
    await createApp($);
    await $.waitUntilVisible($(#counterText));

    // $.platform.tap() should route through DesktopAutomator on desktop.
    // It throws PlatformException('ELEMENT_NOT_FOUND') because there is
    // no native element called 'NonExistentButton', but it must NOT throw
    // UnsupportedError — that would mean the routing is broken.
    try {
      await $.platform.tap(Selector(text: 'NonExistentButton'));
      fail('Should have thrown - no such native element');
    } on Exception catch (e) {
      expect(e.toString(), isNot(contains('Unsupported platform')));
      expect(e.toString(), isNot(contains('No desktop handler')));
      expect(e.toString(), contains('ELEMENT_NOT_FOUND'));
    }
  }, tags: ['desktop']);
}

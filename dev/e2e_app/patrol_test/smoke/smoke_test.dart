import 'package:flutter/material.dart';

import '../common.dart';

void main() {
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

  patrol('platform tap routing works', ($) async {
    await createApp($);
    await $.waitUntilVisible($(#counterText));

    // Short timeout (2s) to avoid blocking the iOS main thread too long —
    // IOSAutomator.waitFor runs on DispatchQueue.main.sync and a long
    // blockage prevents XCTest from terminating the app between tests.
    try {
      await $.platform.tap(
        Selector(text: 'NonExistentButton'),
        timeout: const Duration(seconds: 2),
      );
      fail('Should have thrown - no such native element');
    } on Exception catch (e) {
      expect(e.toString(), isNot(contains('Unsupported platform')));
      expect(e.toString(), isNot(contains('No desktop handler')));
    }
  });
}

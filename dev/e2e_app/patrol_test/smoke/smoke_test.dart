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

}

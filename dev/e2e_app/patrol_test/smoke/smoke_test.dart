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

  patrol('text field entry and replacement', ($) async {
    await createApp($);
    await $.waitUntilVisible($(#counterText));

    await $(#textField).enterText('first input');
    expect($('first input'), findsOneWidget);

    await $(#textField).enterText('replaced');
    expect($('replaced'), findsOneWidget);
    expect($('first input'), findsNothing);
  });

  patrol('scrolling screen with scroll directions', ($) async {
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

    await $.tap($(#backButton));
    await $.scrollUntilVisible(
      finder: $(#counterText),
      scrollDirection: AxisDirection.up,
    );
    expect($(#counterText).text, '0');
  });

  patrol('finder evaluation on visible widgets', ($) async {
    await createApp($);
    await $.waitUntilVisible($(#counterText));

    expect($(#counterText).evaluate(), isNotEmpty);
    expect($(FloatingActionButton).evaluate(), isNotEmpty);
    expect($(#textField).evaluate(), isNotEmpty);
  });

  patrol('multiple rapid taps and state verification', ($) async {
    await createApp($);
    await $.waitUntilVisible($(#counterText));

    for (var i = 0; i < 5; i++) {
      await $(FloatingActionButton).tap();
    }
    expect($(#counterText).text, '5');

    await $(#tile2).scrollTo().tap();
    expect($(#counterText).text, '-5');
  });
}

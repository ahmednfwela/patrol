import 'package:flutter/material.dart';

import '../common.dart';

void main() {
  patrol('pressHome and openApp lifecycle', ($) async {
    await createApp($);
    await $.waitUntilVisible($(#counterText));

    await $(FloatingActionButton).tap();
    expect($(#counterText).text, '1');

    await $.platform.mobile.pressHome();
    await $.platform.mobile.openApp();

    await $.waitUntilVisible($(#counterText));
  });

  patrol('tapAt screen coordinates', ($) async {
    await createApp($);
    await $.waitUntilVisible($(#counterText));

    await $.platform.mobile.tapAt(const Offset(0.5, 0.5));

    await $.waitUntilVisible($(#counterText));
  });

  patrol('swipe gesture on scrolling screen', ($) async {
    await createApp($);
    await $.waitUntilVisible($(#counterText));

    await $('Open scrolling screen').scrollTo().tap();
    await $.waitUntilVisible($(#topText));

    await $.platform.mobile.swipe(
      from: const Offset(0.5, 0.8),
      to: const Offset(0.5, 0.2),
    );

    await $.tap($(#backButton));
  });

  patrol('pullToRefresh on scrolling screen', ($) async {
    await createApp($);
    await $.waitUntilVisible($(#counterText));

    await $('Open scrolling screen').scrollTo().tap();
    await $.waitUntilVisible($(#topText));

    await $.platform.mobile.pullToRefresh();
    await $.waitUntilVisible($(#refreshText));
    expect($('Some text that appeared after refresh'), findsOneWidget);

    await $.tap($(#backButton));
  });

  patrol('getOsVersion returns positive integer', ($) async {
    await createApp($);

    final osVersion = await $.platform.mobile.getOsVersion();
    expect(osVersion, greaterThan(0));
  });

  patrol('isVirtualDevice returns true on emulator', ($) async {
    await createApp($);

    final isVirtual = await $.platform.mobile.isVirtualDevice();
    expect(isVirtual, isTrue);
  });
}

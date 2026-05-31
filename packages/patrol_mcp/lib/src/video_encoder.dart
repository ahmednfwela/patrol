import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'cdp_service.dart';

/// Encodes CDP screencast frames into an animated GIF.
abstract final class VideoEncoder {
  static const _maxHeight = 400;

  static Uint8List encodeGif(List<ScreencastFrame> frames) {
    if (frames.isEmpty) {
      throw ArgumentError('No frames to encode');
    }

    img.Image? animation;

    for (var i = 0; i < frames.length; i++) {
      img.Image? decoded;
      try {
        decoded = img.decodeImage(frames[i].data);
      } on Object {
        continue;
      }
      if (decoded == null) {
        continue;
      }

      final resized = decoded.height > _maxHeight
          ? img.copyResize(decoded, height: _maxHeight)
          : decoded;

      int durationMs;
      if (i + 1 < frames.length) {
        durationMs =
            ((frames[i + 1].timestamp - frames[i].timestamp) * 1000)
                .round()
                .clamp(20, 2000);
      } else {
        durationMs = 100;
      }

      resized.frameDuration = durationMs;

      if (animation == null) {
        animation = resized;
      } else {
        animation.addFrame(resized);
      }
    }

    if (animation == null) {
      throw ArgumentError('No valid frames could be decoded');
    }

    return Uint8List.fromList(img.encodeGif(animation));
  }
}

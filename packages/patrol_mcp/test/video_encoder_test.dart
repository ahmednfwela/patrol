import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:patrol_mcp/src/cdp_service.dart';
import 'package:patrol_mcp/src/video_encoder.dart';
import 'package:test/test.dart';

Uint8List _createJpegFrame({int width = 100, int height = 80}) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(255, 0, 0));
  return Uint8List.fromList(img.encodeJpg(image));
}

void main() {
  group('VideoEncoder', () {
    test('throws on empty frames', () {
      expect(
        () => VideoEncoder.encodeGif([]),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('single frame produces valid GIF', () {
      final frames = [
        ScreencastFrame(data: _createJpegFrame(), timestamp: 1),
      ];

      final gif = VideoEncoder.encodeGif(frames);

      // GIF89a header
      expect(gif[0], 0x47); // G
      expect(gif[1], 0x49); // I
      expect(gif[2], 0x46); // F
      expect(gif[3], 0x38); // 8
      expect(gif[4], 0x39); // 9
      expect(gif[5], 0x61); // a
    });

    test('multiple frames encode with durations', () {
      final frames = [
        ScreencastFrame(data: _createJpegFrame(), timestamp: 1),
        ScreencastFrame(data: _createJpegFrame(), timestamp: 1.1),
        ScreencastFrame(data: _createJpegFrame(), timestamp: 1.3),
      ];

      final gif = VideoEncoder.encodeGif(frames);

      expect(gif.sublist(0, 3), [0x47, 0x49, 0x46]);
      expect(gif.length, greaterThan(100));

      final decoded = img.decodeGif(gif);
      expect(decoded, isNotNull);
      expect(decoded!.numFrames, 3);
    });

    test('frames exceeding max height are resized', () {
      final largeFrame =
          _createJpegFrame(width: 1600, height: 1200);
      final frames = [
        ScreencastFrame(data: largeFrame, timestamp: 1),
      ];

      final gif = VideoEncoder.encodeGif(frames);
      final decoded = img.decodeGif(gif);
      expect(decoded, isNotNull);
      expect(decoded!.height, lessThanOrEqualTo(400));
    });

    test('corrupt frames are skipped, valid ones encoded', () {
      final validFrame = _createJpegFrame();
      final frames = [
        ScreencastFrame(
          data: Uint8List.fromList([0x00, 0x01, 0x02]),
          timestamp: 1,
        ),
        ScreencastFrame(data: validFrame, timestamp: 2),
      ];

      final gif = VideoEncoder.encodeGif(frames);
      expect(gif.sublist(0, 3), [0x47, 0x49, 0x46]);

      final decoded = img.decodeGif(gif);
      expect(decoded, isNotNull);
      expect(decoded!.numFrames, 1);
    });

    test('all corrupt frames throws', () {
      final frames = [
        ScreencastFrame(
          data: Uint8List.fromList([0x00, 0x01]),
          timestamp: 1,
        ),
        ScreencastFrame(
          data: Uint8List.fromList([0x02, 0x03]),
          timestamp: 2,
        ),
      ];

      expect(
        () => VideoEncoder.encodeGif(frames),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}

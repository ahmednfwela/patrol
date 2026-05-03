import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:mcp_dart/mcp_dart.dart';
import 'package:patrol_cli/patrol_cli.dart' show Device, TargetPlatform;
import 'package:patrol_mcp/src/cdp_service.dart';
import 'package:patrol_mcp/src/screenshot_service.dart';
import 'package:test/test.dart';

class _FakeCdpService extends CdpService {
  _FakeCdpService()
      : super(
          debuggerPort: 0,
          wsConnector: (_) => throw UnimplementedError(),
          targetDiscovery: (_) => throw UnimplementedError(),
        );

  // Conflicts with type_annotate_public_apis.
  // ignore: omit_obvious_property_types
  bool captureScreenshotCalled = false;
  Uint8List? screenshotResult;

  @override
  Future<Uint8List> captureScreenshot() async {
    captureScreenshotCalled = true;
    if (screenshotResult != null) {
      return screenshotResult!;
    }
    throw Exception('No screenshot configured');
  }

  @override
  Future<void> connect() async {}
}

const _webDevice = Device(
  name: 'Chrome',
  id: 'chrome',
  targetPlatform: TargetPlatform.web,
  real: false,
);

const _androidDevice = Device(
  name: 'Pixel 6',
  id: 'emulator-5554',
  targetPlatform: TargetPlatform.android,
  real: false,
);

void main() {
  group('ScreenshotService', () {
    test('null device returns error', () async {
      final result =
          await ScreenshotService.handleScreenshotRequest(null);
      expect(result.isError, true);
      expect(
        (result.content.first as TextContent).text,
        contains('No active patrol session'),
      );
    });

    test('web device without port returns error', () async {
      final result =
          await ScreenshotService.handleScreenshotRequest(_webDevice);
      expect(result.isError, true);
      expect(
        (result.content.first as TextContent).text,
        contains('no debugger port'),
      );
    });

    test('web device with CDP service captures screenshot', () async {
      // Create a valid 1x1 PNG
      final image = img.Image(width: 1, height: 1);
      img.fill(image, color: img.ColorRgb8(255, 0, 0));
      final validPng = Uint8List.fromList(img.encodePng(image));

      final fakeCdp = _FakeCdpService()
        ..screenshotResult = validPng;

      final result = await ScreenshotService.handleScreenshotRequest(
        _webDevice,
        webDebuggerPort: 9222,
        cdpService: fakeCdp,
      );

      expect(fakeCdp.captureScreenshotCalled, true);
      expect(result.isError, isNot(true));
      expect(result.content.first, isA<ImageContent>());
      expect(
        (result.content.first as ImageContent).mimeType,
        'image/png',
      );
    });

    test('web device with CDP error returns error result', () async {
      final fakeCdp = _FakeCdpService();

      final result = await ScreenshotService.handleScreenshotRequest(
        _webDevice,
        webDebuggerPort: 9222,
        cdpService: fakeCdp,
      );

      expect(result.isError, true);
      expect(
        (result.content.first as TextContent).text,
        contains('Failed to capture web screenshot'),
      );
    });

    test('android device does not use CDP', () async {
      final fakeCdp = _FakeCdpService();

      final result = await ScreenshotService.handleScreenshotRequest(
        _androidDevice,
        cdpService: fakeCdp,
      );

      expect(fakeCdp.captureScreenshotCalled, false);
      expect(result.isError, true);
    });
  });
}

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:logging/logging.dart' as logging;
import 'package:mcp_dart/mcp_dart.dart';
import 'package:patrol_cli/patrol_cli.dart' show Device, TargetPlatform;

import 'cdp_service.dart';

enum ScreenshotPlatform {
  android('adb', ['exec-out', 'screencap', '-p']),
  ios('xcrun', [
    'simctl',
    'io',
    'booted',
    'screenshot',
    '--type=png',
    '/dev/stdout',
  ]);

  const ScreenshotPlatform(this.command, this.args);

  final String command;
  final List<String> args;

  static ScreenshotPlatform fromDevice(Device device) =>
      switch (device.targetPlatform) {
        TargetPlatform.android => ScreenshotPlatform.android,
        TargetPlatform.iOS => ScreenshotPlatform.ios,
        _ => throw ArgumentError(
          'Native screenshot not supported for platform: '
          '${device.targetPlatform.name}. '
          'Use CDP for web screenshots.',
        ),
      };
}

abstract final class ScreenshotService {
  static final _logger = logging.Logger('ScreenshotService');
  static const _maxHeight = 800;

  static Future<CallToolResult> handleScreenshotRequest(
    Device? device, {
    int? webDebuggerPort,
    CdpService? cdpService,
  }) async {
    try {
      if (device == null) {
        return const CallToolResult(
          content: [
            TextContent(
              text:
                  'No active patrol session. '
                  'Run a test first so the device platform can be detected.',
            ),
          ],
          isError: true,
        );
      }

      if (device.targetPlatform == TargetPlatform.web) {
        return _handleWebScreenshot(
          webDebuggerPort: webDebuggerPort,
          cdpService: cdpService,
        );
      }

      final platform = ScreenshotPlatform.fromDevice(device);
      final bytes = await _captureNativeScreenshot(platform);
      final base64Data = base64Encode(bytes);

      return CallToolResult(
        content: [ImageContent(data: base64Data, mimeType: 'image/png')],
      );
    } catch (e) {
      return CallToolResult(
        content: [TextContent(text: 'Failed to capture screenshot: $e')],
        isError: true,
      );
    }
  }

  static Future<CallToolResult> _handleWebScreenshot({
    int? webDebuggerPort,
    CdpService? cdpService,
  }) async {
    if (webDebuggerPort == null && cdpService == null) {
      return const CallToolResult(
        content: [
          TextContent(
            text: 'Web session detected but no debugger port available. '
                'Ensure the web develop session is fully started.',
          ),
        ],
        isError: true,
      );
    }

    final service =
        cdpService ?? CdpService(debuggerPort: webDebuggerPort!);
    try {
      final bytes = await service.captureScreenshot();
      final resized = _resizeImage(bytes);
      final base64Data = base64Encode(resized);

      return CallToolResult(
        content: [ImageContent(data: base64Data, mimeType: 'image/png')],
      );
    } catch (e) {
      return CallToolResult(
        content: [
          TextContent(text: 'Failed to capture web screenshot via CDP: $e'),
        ],
        isError: true,
      );
    }
  }

  static Future<Uint8List> _captureNativeScreenshot(
    ScreenshotPlatform platform,
  ) async {
    final result = await Process.run(platform.command, platform.args,
        stdoutEncoding: null);

    if (result.exitCode != 0) {
      throw Exception(
        'Failed to capture screenshot: ${result.stderr}',
      );
    }

    final rawBytes = result.stdout as Uint8List;
    _validatePng(rawBytes);
    return _resizeImage(rawBytes);
  }

  static void _validatePng(Uint8List bytes) {
    const pngSignature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

    if (bytes.length >= pngSignature.length &&
        pngSignature.indexed.every((e) => bytes[e.$1] == e.$2)) {
      return;
    }

    final prefixBytes = bytes.length > 512 ? bytes.sublist(0, 512) : bytes;
    final prefix = String.fromCharCodes(
      prefixBytes.where((b) => b >= 0x20 && b < 0x7F),
    );

    throw Exception(
      'screencap returned invalid image data.\n'
      'Output prefix: $prefix',
    );
  }

  static Uint8List _resizeImage(Uint8List bytes) {
    try {
      final image = img.decodeImage(bytes);
      if (image == null || image.height <= _maxHeight) {
        return bytes;
      }

      final resized = img.copyResize(image, height: _maxHeight);
      return Uint8List.fromList(img.encodePng(resized));
    } on Exception catch (e) {
      _logger.warning('Failed to decode/resize image, returning raw: $e');
      return bytes;
    }
  }
}

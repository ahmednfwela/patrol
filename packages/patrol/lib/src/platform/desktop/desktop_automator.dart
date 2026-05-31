import 'package:flutter/services.dart';
import 'package:patrol/src/platform/current.dart' as current_platform;

const _channel = MethodChannel('pl.leancode.patrol/desktopAutomator');

void _defaultLogger(String message) {
  // Logging to console is intentional for test debugging.
  // ignore: avoid_print
  print('DesktopAutomator: $message');
}

/// Configuration for [DesktopAutomator].
class DesktopAutomatorConfig {
  /// Creates a new [DesktopAutomatorConfig].
  const DesktopAutomatorConfig({
    this.findTimeout = const Duration(seconds: 10),
    this.logger = _defaultLogger,
  });

  /// Timeout for finding native UI elements.
  final Duration findTimeout;

  /// Logger function for debug output.
  final void Function(String) logger;
}

/// Provides native UI automation on Linux and Windows desktop platforms.
///
/// On Windows, uses Microsoft UI Automation (COM/UIA). On Linux, uses
/// AT-SPI2 (libatspi) for element discovery and xdotool for input synthesis.
///
/// Communication with the native side happens via a method channel
/// (`pl.leancode.patrol/desktopAutomator`).
class DesktopAutomator {
  /// Creates a new [DesktopAutomator].
  DesktopAutomator({this.config = const DesktopAutomatorConfig()});

  /// The configuration for this automator.
  final DesktopAutomatorConfig config;

  /// Initializes the native automator.
  ///
  /// This is a no-op — native UIA/AT-SPI2 initialization happens lazily
  /// on the first method channel call. We cannot call the channel here
  /// because the Flutter binding may not be initialized yet.
  Future<void> initialize() async {
    config.logger('initialize() - deferred to first native call');
  }

  /// Taps on the native UI element matching the given criteria.
  Future<void> tap({
    String? name,
    String? className,
    String? automationId,
    int? index,
  }) async {
    config.logger('tap(name: $name, className: $className)');
    await _channel.invokeMethod<void>('tap', {
      'name': ?name,
      'className': ?className,
      'automationId': ?automationId,
      'index': ?index,
      'timeoutMs': config.findTimeout.inMilliseconds,
    });
  }

  /// Taps at the given screen coordinates.
  Future<void> tapAt(double x, double y) async {
    config.logger('tapAt($x, $y)');
    await _channel.invokeMethod<void>('tapAt', {'x': x, 'y': y});
  }

  /// Double-taps on the native UI element matching the given criteria.
  Future<void> doubleTap({
    String? name,
    String? className,
    String? automationId,
  }) async {
    config.logger('doubleTap(name: $name)');
    await _channel.invokeMethod<void>('doubleTap', {
      'name': ?name,
      'className': ?className,
      'automationId': ?automationId,
      'timeoutMs': config.findTimeout.inMilliseconds,
    });
  }

  /// Enters text into the native UI element matching the given criteria.
  Future<void> enterText({
    required String text,
    String? name,
    String? className,
    int? index,
  }) async {
    config.logger('enterText(text: $text, name: $name)');
    await _channel.invokeMethod<void>('enterText', {
      'text': text,
      'name': ?name,
      'className': ?className,
      'index': ?index,
      'timeoutMs': config.findTimeout.inMilliseconds,
    });
  }

  /// Returns whether a native UI element matching the criteria is visible.
  Future<bool> isElementVisible({
    String? name,
    String? className,
    String? automationId,
  }) async {
    config.logger('isElementVisible(name: $name)');
    final result = await _channel.invokeMethod<bool>('isElementVisible', {
      'name': ?name,
      'className': ?className,
      'automationId': ?automationId,
    });
    return result ?? false;
  }

  /// Finds a native UI element and returns its properties as a map.
  Future<Map<String, dynamic>?> findElement({
    String? name,
    String? className,
    String? automationId,
  }) async {
    config.logger('findElement(name: $name)');
    final result = await _channel
        .invokeMapMethod<String, dynamic>('findElement', {
          'name': ?name,
          'className': ?className,
          'automationId': ?automationId,
          'timeoutMs': config.findTimeout.inMilliseconds,
        });
    return result;
  }

  /// Finds all native UI elements matching the criteria.
  Future<List<Map<String, dynamic>>> findElements({
    String? name,
    String? className,
  }) async {
    config.logger('findElements(name: $name)');
    final result = await _channel.invokeListMethod<Map<String, dynamic>>(
      'findElements',
      {'name': ?name, 'className': ?className},
    );
    return result ?? [];
  }

  /// Presses a key, optionally with modifier keys.
  Future<void> pressKey(
    int keyCode, {
    bool shift = false,
    bool ctrl = false,
    bool alt = false,
  }) async {
    config.logger('pressKey($keyCode)');
    await _channel.invokeMethod<void>('pressKey', {
      'keyCode': keyCode,
      'shift': shift,
      'ctrl': ctrl,
      'alt': alt,
    });
  }

  /// Signals that the PatrolAppService is ready.
  ///
  /// This is a no-op on desktop — there is no native test runner to signal.
  Future<void> markPatrolAppServiceReady() async {
    config.logger('markPatrolAppServiceReady() - no-op on desktop');
  }

  /// Whether the current platform supports desktop automation.
  static bool get isSupported =>
      current_platform.isLinux || current_platform.isWindows;
}

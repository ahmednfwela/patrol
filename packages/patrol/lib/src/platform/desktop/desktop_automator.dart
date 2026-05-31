import 'dart:io';

import 'package:flutter/services.dart';

const _channel = MethodChannel('pl.leancode.patrol/desktopAutomator');

void _defaultLogger(String message) {
  // ignore: avoid_print
  print('DesktopAutomator: $message');
}

class DesktopAutomatorConfig {
  const DesktopAutomatorConfig({
    this.findTimeout = const Duration(seconds: 10),
    this.logger = _defaultLogger,
  });

  final Duration findTimeout;
  final void Function(String) logger;
}

class DesktopAutomator {
  DesktopAutomator({this.config = const DesktopAutomatorConfig()});

  final DesktopAutomatorConfig config;

  Future<void> initialize() async {
    // No-op: native UIA/AT-SPI2 initialization is lazy (happens on first
    // method channel call). We cannot call the channel here because the
    // Flutter binding may not be initialized yet.
    config.logger('initialize() - deferred to first native call');
  }

  Future<void> tap({
    String? name,
    String? className,
    String? automationId,
    int? index,
  }) async {
    config.logger('tap(name: $name, className: $className)');
    await _channel.invokeMethod<void>('tap', {
      if (name != null) 'name': name,
      if (className != null) 'className': className,
      if (automationId != null) 'automationId': automationId,
      if (index != null) 'index': index,
      'timeoutMs': config.findTimeout.inMilliseconds,
    });
  }

  Future<void> tapAt(double x, double y) async {
    config.logger('tapAt($x, $y)');
    await _channel.invokeMethod<void>('tapAt', {'x': x, 'y': y});
  }

  Future<void> doubleTap({
    String? name,
    String? className,
    String? automationId,
  }) async {
    config.logger('doubleTap(name: $name)');
    await _channel.invokeMethod<void>('doubleTap', {
      if (name != null) 'name': name,
      if (className != null) 'className': className,
      if (automationId != null) 'automationId': automationId,
      'timeoutMs': config.findTimeout.inMilliseconds,
    });
  }

  Future<void> enterText({
    required String text,
    String? name,
    String? className,
    int? index,
  }) async {
    config.logger('enterText(text: $text, name: $name)');
    await _channel.invokeMethod<void>('enterText', {
      'text': text,
      if (name != null) 'name': name,
      if (className != null) 'className': className,
      if (index != null) 'index': index,
      'timeoutMs': config.findTimeout.inMilliseconds,
    });
  }

  Future<bool> isElementVisible({
    String? name,
    String? className,
    String? automationId,
  }) async {
    config.logger('isElementVisible(name: $name)');
    final result = await _channel.invokeMethod<bool>('isElementVisible', {
      if (name != null) 'name': name,
      if (className != null) 'className': className,
      if (automationId != null) 'automationId': automationId,
    });
    return result ?? false;
  }

  Future<Map<String, dynamic>?> findElement({
    String? name,
    String? className,
    String? automationId,
  }) async {
    config.logger('findElement(name: $name)');
    final result = await _channel
        .invokeMapMethod<String, dynamic>('findElement', {
          if (name != null) 'name': name,
          if (className != null) 'className': className,
          if (automationId != null) 'automationId': automationId,
          'timeoutMs': config.findTimeout.inMilliseconds,
        });
    return result;
  }

  Future<List<Map<String, dynamic>>> findElements({
    String? name,
    String? className,
  }) async {
    config.logger('findElements(name: $name)');
    final result = await _channel.invokeListMethod<Map<String, dynamic>>(
      'findElements',
      {
        if (name != null) 'name': name,
        if (className != null) 'className': className,
      },
    );
    return result ?? [];
  }

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

  Future<void> markPatrolAppServiceReady() async {
    config.logger('markPatrolAppServiceReady() - no-op on desktop');
  }

  static bool get isSupported => Platform.isLinux || Platform.isWindows;

  void _warnUnsupported(String method) {
    config.logger('$method is not supported on desktop - skipping');
  }

  Future<void> noopWarn(String method) async => _warnUnsupported(method);
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:logging/logging.dart';

/// A frame captured during CDP screencast recording.
class ScreencastFrame {
  ScreencastFrame({required this.data, required this.timestamp});

  final Uint8List data;
  final double timestamp;
}

/// Chrome DevTools Protocol client for web screenshot and video.
///
/// Connects to a running Chrome instance via its DevTools WebSocket
/// and supports single screenshots and screencast recording.
class CdpService {
  CdpService({
    required int debuggerPort,
    Future<WebSocket> Function(String url)? wsConnector,
    Future<String> Function(int port)? targetDiscovery,
  })  : _debuggerPort = debuggerPort,
        _wsConnector = wsConnector ?? WebSocket.connect,
        _targetDiscovery = targetDiscovery ?? _defaultTargetDiscovery;

  final int _debuggerPort;
  final Future<WebSocket> Function(String url) _wsConnector;
  final Future<String> Function(int port) _targetDiscovery;
  final _logger = Logger('CdpService');

  WebSocket? _ws;
  var _messageId = 0;
  final _pendingRequests = <int, Completer<Map<String, dynamic>>>{};

  var _isRecording = false;
  final _frames = <ScreencastFrame>[];
  Completer<void>? _recordingCompleter;
  static const _commandTimeout = Duration(seconds: 10);

  final _consoleErrors = <String>[];
  final _consoleLogs = <String>[];
  static const _maxConsoleEntries = 500;

  bool get isRecording => _isRecording;

  /// Browser console errors captured via CDP Runtime.exceptionThrown.
  List<String> get consoleErrors => List.unmodifiable(_consoleErrors);

  /// Browser console logs (warn+error level) via CDP Runtime.consoleAPICalled.
  List<String> get consoleLogs => List.unmodifiable(_consoleLogs);

  void clearConsole() {
    _consoleErrors.clear();
    _consoleLogs.clear();
  }

  static Future<String> _defaultTargetDiscovery(int port) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(
        Uri.parse('http://localhost:$port/json'),
      );
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      final targets = jsonDecode(body) as List<dynamic>;

      final pageTarget =
          targets.cast<Map<String, dynamic>>().firstWhere(
            (t) => t['type'] == 'page',
            orElse: () => throw StateError(
              'No page target found in Chrome DevTools targets',
            ),
          );

      return pageTarget['webSocketDebuggerUrl'] as String;
    } finally {
      client.close();
    }
  }

  Future<void> connect() async {
    if (_ws != null) {
      return;
    }

    final wsUrl = await _targetDiscovery(_debuggerPort);
    _logger.info('Connecting to CDP: $wsUrl');

    final ws = await _wsConnector(wsUrl);
    _ws = ws;
    ws.listen(
      _handleMessage,
      onError: (Object error) {
        _logger.warning('CDP WebSocket error: $error');
      },
      onDone: () {
        _logger.info('CDP WebSocket closed');
        _ws = null;
      },
    );

    await _sendCommand('Page.enable');
    await _sendCommand('Runtime.enable');
    await _sendCommand('Log.enable');
  }

  Future<void> disconnect() async {
    _isRecording = false;
    _frames.clear();

    for (final completer in _pendingRequests.values) {
      if (!completer.isCompleted) {
        completer.completeError(
          StateError('CDP disconnected'),
        );
      }
    }
    _pendingRequests.clear();

    final ws = _ws;
    _ws = null;
    if (ws != null) {
      await ws.close();
    }
  }

  Future<Uint8List> captureScreenshot() async {
    await _ensureConnected();
    final result = await _sendCommand('Page.captureScreenshot', {
      'format': 'png',
      'optimizeForSpeed': true,
    });
    return base64Decode(result['data'] as String);
  }

  Future<void> startRecording() async {
    if (_isRecording) {
      throw StateError('Recording already in progress');
    }
    await _ensureConnected();

    _frames.clear();

    await _sendCommand('Page.startScreencast', {
      'format': 'jpeg',
      'quality': 60,
      'maxWidth': 800,
      'maxHeight': 600,
      'everyNthFrame': 6,
    });

    _isRecording = true;
    _recordingCompleter = Completer<void>();
  }

  Future<List<ScreencastFrame>> stopRecording() async {
    if (!_isRecording) {
      throw StateError('No recording in progress');
    }

    _stopRecordingInternal();

    try {
      await _sendCommand('Page.stopScreencast');
    } catch (e) {
      _logger.warning('Error stopping screencast: $e');
    }

    return List.unmodifiable(_frames);
  }

  void _stopRecordingInternal() {
    _isRecording = false;
    if (_recordingCompleter case final c? when !c.isCompleted) {
      c.complete();
    }
    _recordingCompleter = null;
  }

  Future<void> _ensureConnected() async {
    if (_ws == null) {
      await connect();
    }
  }

  Future<Map<String, dynamic>> _sendCommand(
    String method, [
    Map<String, dynamic>? params,
  ]) {
    final ws = _ws;
    if (ws == null) {
      throw StateError('CDP not connected');
    }

    final id = ++_messageId;
    final completer = Completer<Map<String, dynamic>>();
    _pendingRequests[id] = completer;

    final message = <String, dynamic>{
      'id': id,
      'method': method,
    };
    if (params != null) {
      message['params'] = params;
    }
    ws.add(jsonEncode(message));

    return completer.future.timeout(
      _commandTimeout,
      onTimeout: () {
        _pendingRequests.remove(id);
        throw TimeoutException('CDP command "$method" timed out');
      },
    );
  }

  void _handleMessage(dynamic raw) {
    final msg = jsonDecode(raw as String) as Map<String, dynamic>;

    if (msg.containsKey('id')) {
      final id = msg['id'] as int;
      final completer = _pendingRequests.remove(id);
      if (completer == null || completer.isCompleted) {
        return;
      }

      if (msg.containsKey('error')) {
        completer.completeError(
          Exception('CDP error: ${jsonEncode(msg['error'])}'),
        );
      } else {
        completer.complete(
          (msg['result'] as Map<String, dynamic>?) ??
              <String, dynamic>{},
        );
      }
      return;
    }

    final method = msg['method'] as String?;
    final params = msg['params'] as Map<String, dynamic>?;
    switch (method) {
      case 'Page.screencastFrame':
        _handleScreencastFrame(params!);
      case 'Runtime.exceptionThrown':
        _handleException(params!);
      case 'Runtime.consoleAPICalled':
        _handleConsoleCall(params!);
      case 'Log.entryAdded':
        _handleLogEntry(params!);
    }
  }

  void _handleScreencastFrame(Map<String, dynamic> params) {
    final sessionId = params['sessionId'] as int;

    unawaited(
      _sendCommand(
        'Page.screencastFrameAck',
        {'sessionId': sessionId},
      ).onError((e, _) {
        _logger.fine('Frame ack failed (non-fatal): $e');
        return <String, dynamic>{};
      }),
    );

    if (!_isRecording) {
      return;
    }

    final data = base64Decode(params['data'] as String);
    final metadata = params['metadata'] as Map<String, dynamic>;
    final timestamp = (metadata['timestamp'] as num).toDouble();

    _frames.add(ScreencastFrame(
      data: Uint8List.fromList(data),
      timestamp: timestamp,
    ));
  }

  void _handleException(Map<String, dynamic> params) {
    final details = params['exceptionDetails'] as Map<String, dynamic>?;
    if (details == null) {
      return;
    }
    final text = details['text'] as String? ?? '';
    final exception = details['exception'] as Map<String, dynamic>?;
    final description =
        exception?['description'] as String? ??
        exception?['value'] as String? ??
        '';
    final message = description.isNotEmpty ? '$text: $description' : text;
    _pushConsoleError('[EXCEPTION] $message');
  }

  void _handleConsoleCall(Map<String, dynamic> params) {
    final type = params['type'] as String? ?? '';
    if (type != 'error' && type != 'warning') {
      return;
    }
    final args = params['args'] as List<dynamic>? ?? [];
    final parts = <String>[];
    for (final arg in args) {
      final a = arg as Map<String, dynamic>;
      final value = a['value'] ?? a['description'] ?? a['unserializableValue'];
      if (value != null) {
        parts.add('$value');
      }
    }
    if (parts.isNotEmpty) {
      _pushConsoleLog('[${type.toUpperCase()}] ${parts.join(' ')}');
    }
  }

  void _handleLogEntry(Map<String, dynamic> params) {
    final entry = params['entry'] as Map<String, dynamic>? ?? params;
    final level = entry['level'] as String? ?? '';
    if (level != 'error' && level != 'warning') {
      return;
    }
    final text = entry['text'] as String? ?? '';
    if (text.isNotEmpty) {
      _pushConsoleLog('[LOG:${level.toUpperCase()}] $text');
    }
  }

  void _pushConsoleError(String message) {
    _consoleErrors.add(message);
    if (_consoleErrors.length > _maxConsoleEntries) {
      _consoleErrors.removeRange(
        0,
        _consoleErrors.length - _maxConsoleEntries,
      );
    }
    _logger.warning('Browser: $message');
  }

  void _pushConsoleLog(String message) {
    _consoleLogs.add(message);
    if (_consoleLogs.length > _maxConsoleEntries) {
      _consoleLogs.removeRange(
        0,
        _consoleLogs.length - _maxConsoleEntries,
      );
    }
    _logger.info('Browser: $message');
  }
}

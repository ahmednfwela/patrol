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

  bool get isRecording => _isRecording;

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
    if (method == 'Page.screencastFrame') {
      _handleScreencastFrame(
        msg['params'] as Map<String, dynamic>,
      );
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
}

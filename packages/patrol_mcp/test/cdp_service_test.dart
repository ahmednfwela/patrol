import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:patrol_mcp/src/cdp_service.dart';
import 'package:test/test.dart';

class _MockWebSocket implements WebSocket {
  final _controller = StreamController<dynamic>.broadcast();
  // Conflicts with type_annotate_public_apis.
  // ignore: omit_obvious_property_types
  final List<String> sent = <String>[];
  // Conflicts with type_annotate_public_apis.
  // ignore: omit_obvious_property_types
  bool closed = false;

  void receiveMessage(Map<String, dynamic> msg) {
    _controller.add(jsonEncode(msg));
  }

  @override
  void add(dynamic data) {
    sent.add(data as String);
  }

  @override
  Future<void> close([int? code, String? reason]) async {
    closed = true;
    await _controller.close();
  }

  @override
  StreamSubscription<dynamic> listen(
    void Function(dynamic)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) =>
      _controller.stream.listen(
        onData,
        onError: onError,
        onDone: onDone,
        cancelOnError: cancelOnError,
      );

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

const _fakeWsUrl = 'ws://localhost:9222/devtools/page/TEST';

CdpService _createService({_MockWebSocket? ws}) {
  final mockWs = ws ?? _MockWebSocket();
  return CdpService(
    debuggerPort: 9222,
    wsConnector: (url) async => mockWs,
    targetDiscovery: (port) async => _fakeWsUrl,
  );
}

Map<String, dynamic> _parseMessage(String raw) =>
    jsonDecode(raw) as Map<String, dynamic>;

void main() {
  group('CdpService', () {
    test('connect sends Page.enable', () async {
      final ws = _MockWebSocket();
      final service = _createService(ws: ws);

      final connectFuture = service.connect();

      await Future<void>.delayed(Duration.zero);
      expect(ws.sent, hasLength(1));

      final msg = _parseMessage(ws.sent.first);
      expect(msg['method'], 'Page.enable');
      expect(msg['id'], 1);

      ws.receiveMessage(<String, dynamic>{'id': 1, 'result': <String, dynamic>{}});
      await connectFuture;
    });

    test('captureScreenshot sends correct command', () async {
      final ws = _MockWebSocket();
      final service = _createService(ws: ws);

      final connectFuture = service.connect();
      await Future<void>.delayed(Duration.zero);
      ws.receiveMessage(<String, dynamic>{'id': 1, 'result': <String, dynamic>{}});
      await connectFuture;

      final screenshotFuture = service.captureScreenshot();
      await Future<void>.delayed(Duration.zero);

      expect(ws.sent, hasLength(2));
      final msg = _parseMessage(ws.sent[1]);
      expect(msg['method'], 'Page.captureScreenshot');
      expect((msg['params'] as Map)['format'], 'png');
      expect((msg['params'] as Map)['optimizeForSpeed'], true);

      final fakeData = base64Encode([0x89, 0x50, 0x4E, 0x47]);
      ws.receiveMessage(<String, dynamic>{
        'id': 2,
        'result': <String, dynamic>{'data': fakeData},
      });

      final bytes = await screenshotFuture;
      expect(bytes, [0x89, 0x50, 0x4E, 0x47]);
    });

    test('CDP error response propagates as exception', () async {
      final ws = _MockWebSocket();
      final service = _createService(ws: ws);

      final connectFuture = service.connect();
      await Future<void>.delayed(Duration.zero);
      ws.receiveMessage(<String, dynamic>{'id': 1, 'result': <String, dynamic>{}});
      await connectFuture;

      final screenshotFuture = service.captureScreenshot();
      await Future<void>.delayed(Duration.zero);

      ws.receiveMessage(<String, dynamic>{
        'id': 2,
        'error': <String, dynamic>{'code': -32000, 'message': 'Page not found'},
      });

      await expectLater(screenshotFuture, throwsException);
    });

    test('command timeout fires after duration', () async {
      final ws = _MockWebSocket();
      final service = _createService(ws: ws);

      final connectFuture = service.connect();
      await Future<void>.delayed(Duration.zero);
      ws.receiveMessage(<String, dynamic>{'id': 1, 'result': <String, dynamic>{}});
      await connectFuture;

      await expectLater(
        service.captureScreenshot(),
        throwsA(isA<TimeoutException>()),
      );
    }, timeout: const Timeout(Duration(seconds: 15)));

    test('recording state machine', () async {
      final ws = _MockWebSocket();
      final service = _createService(ws: ws);

      final connectFuture = service.connect();
      await Future<void>.delayed(Duration.zero);
      ws.receiveMessage(<String, dynamic>{'id': 1, 'result': <String, dynamic>{}});
      await connectFuture;

      expect(service.isRecording, false);

      final startFuture = service.startRecording();
      await Future<void>.delayed(Duration.zero);
      ws.receiveMessage(<String, dynamic>{'id': 2, 'result': <String, dynamic>{}});
      await startFuture;

      expect(service.isRecording, true);

      expect(
        service.startRecording,
        throwsA(isA<StateError>()),
      );

      final stopFuture = service.stopRecording();
      await Future<void>.delayed(Duration.zero);
      ws.receiveMessage(<String, dynamic>{'id': 3, 'result': <String, dynamic>{}});
      final frames = await stopFuture;

      expect(service.isRecording, false);
      expect(frames, isEmpty);

      expect(
        service.stopRecording,
        throwsA(isA<StateError>()),
      );
    });

    test('screencast frames are collected and acked', () async {
      final ws = _MockWebSocket();
      final service = _createService(ws: ws);

      final connectFuture = service.connect();
      await Future<void>.delayed(Duration.zero);
      ws.receiveMessage(<String, dynamic>{'id': 1, 'result': <String, dynamic>{}});
      await connectFuture;

      final startFuture = service.startRecording();
      await Future<void>.delayed(Duration.zero);
      ws.receiveMessage(<String, dynamic>{'id': 2, 'result': <String, dynamic>{}});
      await startFuture;

      final frameData = base64Encode([0xFF, 0xD8, 0xFF, 0xE0]);
      ws.receiveMessage(<String, dynamic>{
        'method': 'Page.screencastFrame',
        'params': <String, dynamic>{
          'data': frameData,
          'metadata': <String, dynamic>{'timestamp': 1000.5},
          'sessionId': 1,
        },
      });
      await Future<void>.delayed(Duration.zero);

      final ackMessages = ws.sent
          .map(_parseMessage)
          .where((m) => m['method'] == 'Page.screencastFrameAck')
          .toList();
      expect(ackMessages, hasLength(1));
      expect(
        (ackMessages.first['params'] as Map)['sessionId'],
        1,
      );

      final stopFuture = service.stopRecording();
      await Future<void>.delayed(Duration.zero);
      ws.receiveMessage(<String, dynamic>{'id': 4, 'result': <String, dynamic>{}});
      final frames = await stopFuture;

      expect(frames, hasLength(1));
      expect(frames.first.data, [0xFF, 0xD8, 0xFF, 0xE0]);
      expect(frames.first.timestamp, 1000.5);
    });

    test('disconnect cleans up state', () async {
      final ws = _MockWebSocket();
      final service = _createService(ws: ws);

      final connectFuture = service.connect();
      await Future<void>.delayed(Duration.zero);
      ws.receiveMessage(<String, dynamic>{'id': 1, 'result': <String, dynamic>{}});
      await connectFuture;

      await service.disconnect();
      expect(ws.closed, true);
      expect(service.isRecording, false);
    });

    test('auto-incrementing message IDs', () async {
      final ws = _MockWebSocket();
      final service = _createService(ws: ws);

      final connectFuture = service.connect();
      await Future<void>.delayed(Duration.zero);
      ws.receiveMessage(<String, dynamic>{'id': 1, 'result': <String, dynamic>{}});
      await connectFuture;

      final f1 = service.captureScreenshot();
      await Future<void>.delayed(Duration.zero);
      final f2 = service.captureScreenshot();
      await Future<void>.delayed(Duration.zero);

      final ids = ws.sent
          .map((s) => _parseMessage(s)['id'] as int)
          .toList();
      // Page.enable=1, screenshot=2, screenshot=3
      expect(ids, [1, 2, 3]);

      final fakeData = base64Encode([0x89]);
      ws
        ..receiveMessage(<String, dynamic>{'id': 2, 'result': <String, dynamic>{'data': fakeData}})
        ..receiveMessage(<String, dynamic>{'id': 3, 'result': <String, dynamic>{'data': fakeData}});

      await f1;
      await f2;
    });

    test('startScreencast sends correct parameters', () async {
      final ws = _MockWebSocket();
      final service = _createService(ws: ws);

      final connectFuture = service.connect();
      await Future<void>.delayed(Duration.zero);
      ws.receiveMessage(<String, dynamic>{'id': 1, 'result': <String, dynamic>{}});
      await connectFuture;

      final startFuture = service.startRecording();
      await Future<void>.delayed(Duration.zero);

      // Find the startScreencast command
      final startMsg = ws.sent
          .map(_parseMessage)
          .firstWhere((m) => m['method'] == 'Page.startScreencast');
      final params = startMsg['params'] as Map<String, dynamic>;

      expect(params['format'], 'jpeg');
      expect(params['quality'], 60);
      expect(params['maxWidth'], 800);
      expect(params['maxHeight'], 600);
      expect(params['everyNthFrame'], 6);

      ws.receiveMessage(<String, dynamic>{'id': 2, 'result': <String, dynamic>{}});
      await startFuture;

      // Cleanup
      final stopFuture = service.stopRecording();
      await Future<void>.delayed(Duration.zero);
      ws.receiveMessage(<String, dynamic>{'id': 3, 'result': <String, dynamic>{}});
      await stopFuture;
    });

    test('failed startScreencast does not set isRecording', () async {
      final ws = _MockWebSocket();
      final service = _createService(ws: ws);

      final connectFuture = service.connect();
      await Future<void>.delayed(Duration.zero);
      ws.receiveMessage(<String, dynamic>{'id': 1, 'result': <String, dynamic>{}});
      await connectFuture;

      final startFuture = service.startRecording();
      await Future<void>.delayed(Duration.zero);

      // Respond with CDP error
      ws.receiveMessage(<String, dynamic>{
        'id': 2,
        'error': <String, dynamic>{
          'code': -32000,
          'message': 'Screencast not supported',
        },
      });

      await expectLater(startFuture, throwsException);
      expect(service.isRecording, false);
    });

    test('frames received while not recording are ignored', () async {
      final ws = _MockWebSocket();
      final service = _createService(ws: ws);

      final connectFuture = service.connect();
      await Future<void>.delayed(Duration.zero);
      ws.receiveMessage(<String, dynamic>{
        'id': 1,
        'result': <String, dynamic>{},
      });
      await connectFuture;

      // Send frame while NOT recording
      final frameData = base64Encode([0xFF, 0xD8, 0xFF, 0xE0]);
      ws.receiveMessage(<String, dynamic>{
        'method': 'Page.screencastFrame',
        'params': <String, dynamic>{
          'data': frameData,
          'metadata': <String, dynamic>{'timestamp': 1.0},
          'sessionId': 1,
        },
      });
      await Future<void>.delayed(Duration.zero);

      // ACK should still be sent (CDP requires it regardless)
      final ackMessages = ws.sent
          .map(_parseMessage)
          .where((m) => m['method'] == 'Page.screencastFrameAck')
          .toList();
      expect(ackMessages, hasLength(1));

      // But no frames collected
      expect(service.isRecording, false);
    });

    test('disconnect during pending command completes with error',
        () async {
      final ws = _MockWebSocket();
      final service = _createService(ws: ws);

      final connectFuture = service.connect();
      await Future<void>.delayed(Duration.zero);
      ws.receiveMessage(<String, dynamic>{
        'id': 1,
        'result': <String, dynamic>{},
      });
      await connectFuture;

      // Start a screenshot but don't respond — capture the future
      // before disconnecting so the error doesn't go unhandled.
      var caughtError = false;
      final screenshotFuture =
          service.captureScreenshot().then<void>((_) {}).catchError(
        (Object _) {
          caughtError = true;
        },
      );

      await Future<void>.delayed(Duration.zero);

      // Disconnect while command is pending
      await service.disconnect();

      await screenshotFuture;
      expect(caughtError, true);
    });
  });
}

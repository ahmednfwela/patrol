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

/// Connect sends Page.enable, Runtime.enable, Log.enable (3 commands).
/// This helper responds to all 3 and awaits connect().
Future<void> _completeConnect(_MockWebSocket ws, CdpService service) async {
  final connectFuture = service.connect();
  for (var id = 1; id <= 3; id++) {
    await Future<void>.delayed(Duration.zero);
    ws.receiveMessage(<String, dynamic>{
      'id': id,
      'result': <String, dynamic>{},
    });
  }
  await connectFuture;
}

/// The next command ID after connect (3 enable commands = IDs 1,2,3).
const _postConnectId = 4;

void main() {
  group('CdpService', () {
    test('connect sends Page.enable, Runtime.enable, Log.enable', () async {
      final ws = _MockWebSocket();
      final service = _createService(ws: ws);

      await _completeConnect(ws, service);

      final methods = ws.sent.map(_parseMessage).map((m) => m['method']);
      expect(methods, ['Page.enable', 'Runtime.enable', 'Log.enable']);
    });

    test('captureScreenshot sends correct command', () async {
      final ws = _MockWebSocket();
      final service = _createService(ws: ws);
      await _completeConnect(ws, service);

      final screenshotFuture = service.captureScreenshot();
      await Future<void>.delayed(Duration.zero);

      final msg = ws.sent
          .map(_parseMessage)
          .firstWhere((m) => m['method'] == 'Page.captureScreenshot');
      expect((msg['params'] as Map)['format'], 'png');
      expect((msg['params'] as Map)['optimizeForSpeed'], true);

      final fakeData = base64Encode([0x89, 0x50, 0x4E, 0x47]);
      ws.receiveMessage(<String, dynamic>{
        'id': _postConnectId,
        'result': <String, dynamic>{'data': fakeData},
      });

      final bytes = await screenshotFuture;
      expect(bytes, [0x89, 0x50, 0x4E, 0x47]);
    });

    test('CDP error response propagates as exception', () async {
      final ws = _MockWebSocket();
      final service = _createService(ws: ws);
      await _completeConnect(ws, service);

      final screenshotFuture = service.captureScreenshot();
      await Future<void>.delayed(Duration.zero);

      ws.receiveMessage(<String, dynamic>{
        'id': _postConnectId,
        'error': <String, dynamic>{
          'code': -32000,
          'message': 'Page not found',
        },
      });

      await expectLater(screenshotFuture, throwsException);
    });

    test('command timeout fires after duration', () async {
      final ws = _MockWebSocket();
      final service = _createService(ws: ws);
      await _completeConnect(ws, service);

      // Don't respond — should timeout
      await expectLater(
        service.captureScreenshot(),
        throwsA(isA<TimeoutException>()),
      );
    }, timeout: const Timeout(Duration(seconds: 15)));

    test('recording state machine', () async {
      final ws = _MockWebSocket();
      final service = _createService(ws: ws);
      await _completeConnect(ws, service);

      expect(service.isRecording, false);

      final startFuture = service.startRecording();
      await Future<void>.delayed(Duration.zero);
      ws.receiveMessage(<String, dynamic>{
        'id': _postConnectId,
        'result': <String, dynamic>{},
      });
      await startFuture;

      expect(service.isRecording, true);
      expect(service.startRecording, throwsA(isA<StateError>()));

      final stopFuture = service.stopRecording();
      await Future<void>.delayed(Duration.zero);
      ws.receiveMessage(<String, dynamic>{
        'id': _postConnectId + 1,
        'result': <String, dynamic>{},
      });
      final frames = await stopFuture;

      expect(service.isRecording, false);
      expect(frames, isEmpty);
      expect(service.stopRecording, throwsA(isA<StateError>()));
    });

    test('screencast frames are collected and acked', () async {
      final ws = _MockWebSocket();
      final service = _createService(ws: ws);
      await _completeConnect(ws, service);

      final startFuture = service.startRecording();
      await Future<void>.delayed(Duration.zero);
      ws.receiveMessage(<String, dynamic>{
        'id': _postConnectId,
        'result': <String, dynamic>{},
      });
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
      expect((ackMessages.first['params'] as Map)['sessionId'], 1);

      final stopFuture = service.stopRecording();
      await Future<void>.delayed(Duration.zero);
      ws.receiveMessage(<String, dynamic>{
        'id': _postConnectId + 2,
        'result': <String, dynamic>{},
      });
      final frames = await stopFuture;

      expect(frames, hasLength(1));
      expect(frames.first.data, [0xFF, 0xD8, 0xFF, 0xE0]);
      expect(frames.first.timestamp, 1000.5);
    });

    test('disconnect cleans up state', () async {
      final ws = _MockWebSocket();
      final service = _createService(ws: ws);
      await _completeConnect(ws, service);

      await service.disconnect();
      expect(ws.closed, true);
      expect(service.isRecording, false);
    });

    test('auto-incrementing message IDs', () async {
      final ws = _MockWebSocket();
      final service = _createService(ws: ws);
      await _completeConnect(ws, service);

      final f1 = service.captureScreenshot();
      await Future<void>.delayed(Duration.zero);
      final f2 = service.captureScreenshot();
      await Future<void>.delayed(Duration.zero);

      final ids = ws.sent
          .map((s) => _parseMessage(s)['id'] as int)
          .toList();
      // Page.enable=1, Runtime.enable=2, Log.enable=3, screenshot=4,5
      expect(ids, [1, 2, 3, _postConnectId, _postConnectId + 1]);

      final fakeData = base64Encode([0x89]);
      ws
        ..receiveMessage(<String, dynamic>{
          'id': _postConnectId,
          'result': <String, dynamic>{'data': fakeData},
        })
        ..receiveMessage(<String, dynamic>{
          'id': _postConnectId + 1,
          'result': <String, dynamic>{'data': fakeData},
        });

      await f1;
      await f2;
    });

    test('startScreencast sends correct parameters', () async {
      final ws = _MockWebSocket();
      final service = _createService(ws: ws);
      await _completeConnect(ws, service);

      final startFuture = service.startRecording();
      await Future<void>.delayed(Duration.zero);

      final startMsg = ws.sent
          .map(_parseMessage)
          .firstWhere((m) => m['method'] == 'Page.startScreencast');
      final params = startMsg['params'] as Map<String, dynamic>;

      expect(params['format'], 'jpeg');
      expect(params['quality'], 60);
      expect(params['maxWidth'], 800);
      expect(params['maxHeight'], 600);
      expect(params['everyNthFrame'], 6);

      ws.receiveMessage(<String, dynamic>{
        'id': _postConnectId,
        'result': <String, dynamic>{},
      });
      await startFuture;

      final stopFuture = service.stopRecording();
      await Future<void>.delayed(Duration.zero);
      ws.receiveMessage(<String, dynamic>{
        'id': _postConnectId + 1,
        'result': <String, dynamic>{},
      });
      await stopFuture;
    });

    test('failed startScreencast does not set isRecording', () async {
      final ws = _MockWebSocket();
      final service = _createService(ws: ws);
      await _completeConnect(ws, service);

      final startFuture = service.startRecording();
      await Future<void>.delayed(Duration.zero);

      ws.receiveMessage(<String, dynamic>{
        'id': _postConnectId,
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
      await _completeConnect(ws, service);

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

      final ackMessages = ws.sent
          .map(_parseMessage)
          .where((m) => m['method'] == 'Page.screencastFrameAck')
          .toList();
      expect(ackMessages, hasLength(1));
      expect(service.isRecording, false);
    });

    test('disconnect during pending command completes with error', () async {
      final ws = _MockWebSocket();
      final service = _createService(ws: ws);
      await _completeConnect(ws, service);

      var caughtError = false;
      final screenshotFuture =
          service.captureScreenshot().then<void>((_) {}).catchError(
        (Object _) {
          caughtError = true;
        },
      );

      await Future<void>.delayed(Duration.zero);
      await service.disconnect();
      await screenshotFuture;
      expect(caughtError, true);
    });

    test('console errors are captured via Runtime.exceptionThrown', () async {
      final ws = _MockWebSocket();
      final service = _createService(ws: ws);
      await _completeConnect(ws, service);

      ws.receiveMessage(<String, dynamic>{
        'method': 'Runtime.exceptionThrown',
        'params': <String, dynamic>{
          'timestamp': 1234.0,
          'exceptionDetails': <String, dynamic>{
            'text': 'Uncaught',
            'exception': <String, dynamic>{
              'description': 'Error: Something broke',
            },
          },
        },
      });
      await Future<void>.delayed(Duration.zero);

      expect(service.consoleErrors, hasLength(1));
      expect(service.consoleErrors.first, contains('Something broke'));
    });

    test('console warnings are captured via Runtime.consoleAPICalled',
        () async {
      final ws = _MockWebSocket();
      final service = _createService(ws: ws);
      await _completeConnect(ws, service);

      ws.receiveMessage(<String, dynamic>{
        'method': 'Runtime.consoleAPICalled',
        'params': <String, dynamic>{
          'type': 'error',
          'args': <dynamic>[
            <String, dynamic>{'type': 'string', 'value': 'Test failed'},
          ],
        },
      });
      await Future<void>.delayed(Duration.zero);

      expect(service.consoleLogs, hasLength(1));
      expect(service.consoleLogs.first, contains('Test failed'));
    });

    test('clearConsole resets captured errors and logs', () async {
      final ws = _MockWebSocket();
      final service = _createService(ws: ws);
      await _completeConnect(ws, service);

      ws.receiveMessage(<String, dynamic>{
        'method': 'Runtime.exceptionThrown',
        'params': <String, dynamic>{
          'timestamp': 1.0,
          'exceptionDetails': <String, dynamic>{
            'text': 'err',
            'exception': <String, dynamic>{'value': 'x'},
          },
        },
      });
      await Future<void>.delayed(Duration.zero);
      expect(service.consoleErrors, isNotEmpty);

      service.clearConsole();
      expect(service.consoleErrors, isEmpty);
      expect(service.consoleLogs, isEmpty);
    });
  });
}

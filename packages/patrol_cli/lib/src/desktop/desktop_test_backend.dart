import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dispose_scope/dispose_scope.dart';
import 'package:patrol_cli/src/base/exceptions.dart';
import 'package:patrol_cli/src/base/logger.dart';
import 'package:patrol_cli/src/base/process.dart';
import 'package:patrol_cli/src/crossplatform/app_options.dart';
import 'package:patrol_cli/src/devices.dart';
import 'package:process/process.dart';

const _kServerReadyTimeout = Duration(seconds: 60);
const _kServerPollInterval = Duration(milliseconds: 500);

class DesktopTestBackend {
  DesktopTestBackend({
    required ProcessManager processManager,
    required DisposeScope parentDisposeScope,
    required Logger logger,
  }) : _processManager = processManager,
       _logger = logger,
       _disposeScope = DisposeScope() {
    _disposeScope.disposedBy(parentDisposeScope);
  }

  final ProcessManager _processManager;
  final Logger _logger;
  final DisposeScope _disposeScope;

  /// The VM service URI captured from the last launched app's stdout.
  /// Available for coverage collection after the app starts.
  Uri? _lastVmServiceUri;

  Future<void> build(DesktopAppOptions options) async {
    await _disposeScope.run((scope) async {
      final subject = options.description;
      final task = _logger.task(
        'Building $subject (${options.flutter.buildMode.name})',
      );

      var buildKilled = false;
      final process = await _processManager.start(
        options.toFlutterBuildInvocation(),
        runInShell: true,
      );
      scope.addDispose(() {
        process.kill();
        buildKilled = true;
      });
      process.listenStdOut((l) => _logger.detail('\t$l')).disposedBy(scope);
      process.listenStdErr((l) => _logger.err('\t$l')).disposedBy(scope);

      final exitCode = await process.exitCode;
      final flutterCommand = options.flutter.command;
      if (exitCode != 0) {
        final cause =
            '`$flutterCommand build ${options.platformName}` exited with code $exitCode';
        task.fail('Failed to build $subject ($cause)');
        throwToolExit(cause);
      } else if (buildKilled) {
        final cause =
            '`$flutterCommand build ${options.platformName}` was interrupted';
        task.fail('Failed to build $subject ($cause)');
        throwToolInterrupted(cause);
      }

      task.complete('Completed building $subject');
    });
  }

  Future<void> execute(
    DesktopAppOptions options,
    Device device, {
    bool showFlutterLogs = false,
    bool hideTestSteps = false,
    bool clearTestSteps = false,
  }) async {
    final subject = '${options.description} on ${device.description}';
    final task = _logger.task('Running $subject');

    final port = options.appServerPort;
    final baseUri = Uri.parse('http://localhost:$port');

    try {
      // Discovery pass: launch app, list tests, run first test
      final testNames = <String>[];
      var passCount = 0;
      var failCount = 0;
      var skipCount = 0;

      {
        final appProcess = await _launchApp(options);
        try {
          await _waitForAppServiceOrCrash(baseUri, appProcess);

          final tests = await _listDartTests(baseUri);
          testNames.addAll(tests);

          if (testNames.isEmpty) {
            _logger.warn('No tests discovered');
            task.complete('No tests found in $subject');
            return;
          }

          _logger.info('Discovered ${testNames.length} test(s)');
          for (final name in testNames) {
            _logger.detail('  - $name');
          }

          // Run the first test in this same session
          final result = await _runDartTest(baseUri, testNames.first);
          _logTestResult(testNames.first, result);
          switch (result) {
            case 'success':
              passCount++;
            case 'skipped':
              skipCount++;
            default:
              failCount++;
          }
        } finally {
          await _killProcess(appProcess);
        }
      }

      // Run remaining tests, each in a fresh app launch
      for (var i = 1; i < testNames.length; i++) {
        final testName = testNames[i];
        final appProcess = await _launchApp(options);
        try {
          await _waitForAppServiceOrCrash(baseUri, appProcess);
          final result = await _runDartTest(baseUri, testName);
          _logTestResult(testName, result);
          switch (result) {
            case 'success':
              passCount++;
            case 'skipped':
              skipCount++;
            default:
              failCount++;
          }
        } finally {
          await _killProcess(appProcess);
        }
      }

      _logger.info(
        'Results: $passCount passed, $failCount failed, $skipCount skipped '
        '(${testNames.length} total)',
      );

      if (failCount > 0) {
        task.fail('Tests failed for $subject');
        throwToolExit('$failCount test(s) failed');
      } else {
        task.complete('Completed executing $subject');
      }
    } catch (e) {
      if (e is ToolExit || e is ToolInterrupted) {
        rethrow;
      }
      task.fail('Failed to execute tests of $subject ($e)');
      rethrow;
    }
  }

  Future<Process> _launchApp(DesktopAppOptions options) async {
    final port = options.appServerPort;

    _lastVmServiceUri = null;
    final binaryPath = _findBuiltBinary(options);
    _logger.detail(
      'Launching $binaryPath with PATROL_APP_SERVER_PORT=$port baked in',
    );

    final binaryDir = File(binaryPath).parent.path;
    final process = await _processManager.start([
      binaryPath,
    ], workingDirectory: binaryDir);

    process
        .listenStdOut((l) {
          _logger.detail('[app] $l');
          if (l.contains('listening on http') && _lastVmServiceUri == null) {
            final match = RegExp('listening on (http.+)').firstMatch(l);
            if (match != null) {
              _lastVmServiceUri = Uri.parse(match.group(1)!);
              _logger.detail('Captured VM service URI: $_lastVmServiceUri');
            }
          }
        })
        .disposedBy(_disposeScope);
    process
        .listenStdErr((l) => _logger.detail('[app:err] $l'))
        .disposedBy(_disposeScope);

    return process;
  }

  String _findBuiltBinary(DesktopAppOptions options) {
    final mode = options.flutter.buildMode.name;
    final modeCap = mode[0].toUpperCase() + mode.substring(1);

    if (options.platform == TargetPlatform.windows) {
      final dir = Directory('build/windows/x64/runner/$modeCap');
      if (dir.existsSync()) {
        final exes = dir
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.exe'))
            .toList();
        if (exes.isNotEmpty) {
          return exes.first.absolute.path;
        }
      }
    } else {
      final dir = Directory('build/linux/x64/$mode/bundle');
      if (dir.existsSync()) {
        final bins = dir.listSync().whereType<File>().where((f) {
          final stat = f.statSync();
          return stat.mode & 0x49 != 0;
        }).toList();
        if (bins.isNotEmpty) {
          return bins.first.absolute.path;
        }
      }
    }

    throwToolExit(
      'Could not find built ${options.platformName} binary in build/ directory. '
      'Ensure the build step completed successfully.',
    );
  }

  Future<void> _waitForAppServiceOrCrash(
    Uri baseUri,
    Process appProcess,
  ) async {
    _logger.detail('Waiting for PatrolAppService at $baseUri ...');
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);

    final serverReady = () async {
      final deadline = DateTime.now().add(_kServerReadyTimeout);
      while (DateTime.now().isBefore(deadline)) {
        try {
          final request = await client.getUrl(
            baseUri.replace(path: 'listDartTests'),
          );
          final response = await request.close();
          await response.drain<void>();
          if (response.statusCode == 200) {
            _logger.detail('PatrolAppService is ready');
            return;
          }
        } on SocketException {
          // Server not up yet
        } on HttpException {
          // Server not up yet
        } on OSError {
          // Server not up yet
        }
        await Future<void>.delayed(_kServerPollInterval);
      }
      throwToolExit(
        'Timed out waiting for PatrolAppService to start on $baseUri '
        '(after ${_kServerReadyTimeout.inSeconds}s)',
      );
    }();

    final appCrash = appProcess.exitCode.then((code) {
      throwToolExit(
        'App exited with code $code before PatrolAppService was ready',
      );
    });

    try {
      await Future.any([serverReady, appCrash]);
    } finally {
      client.close();
    }
  }

  Future<List<String>> _listDartTests(Uri baseUri) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client.getUrl(
        baseUri.replace(path: 'listDartTests'),
      );
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode != 200) {
        throwToolExit(
          'listDartTests failed (status ${response.statusCode}): $body',
        );
      }
      final json = jsonDecode(body) as Map<String, dynamic>;
      final group = json['group'] as Map<String, dynamic>;
      return _flattenTests(group, '');
    } finally {
      client.close();
    }
  }

  List<String> _flattenTests(Map<String, dynamic> group, String prefix) {
    final name = group['name'] as String;
    final type = group['type'] as String;
    final entries = group['entries'] as List<dynamic>? ?? [];

    final fullName = prefix.isEmpty ? name : '$prefix $name';

    if (type == 'test') {
      if (name == 'patrol_test_explorer') {
        return [];
      }
      return [fullName.trim()];
    }

    final tests = <String>[];
    for (final entry in entries) {
      tests.addAll(_flattenTests(entry as Map<String, dynamic>, fullName));
    }
    return tests;
  }

  Future<String> _runDartTest(Uri baseUri, String testName) async {
    _logger.info('Running test: $testName');
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client.postUrl(
        baseUri.replace(path: 'runDartTest'),
      );
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({'name': testName}));
      final response = await request.close().timeout(
        const Duration(minutes: 10),
        onTimeout: () => throw TimeoutException(
          'Test "$testName" did not complete within 10 minutes',
        ),
      );
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode != 200) {
        throwToolExit(
          'runDartTest failed (status ${response.statusCode}): $body',
        );
      }
      final json = jsonDecode(body) as Map<String, dynamic>;
      return json['result'] as String? ?? 'failure';
    } finally {
      client.close();
    }
  }

  void _logTestResult(String testName, String result) {
    switch (result) {
      case 'success':
        _logger.info('  ✓ $testName');
      case 'skipped':
        _logger.info('  ○ $testName (skipped)');
      default:
        _logger.err('  ✗ $testName (FAILED)');
    }
  }

  Future<void> _killProcess(Process process) async {
    process.kill();
    try {
      await process.exitCode.timeout(const Duration(seconds: 5));
    } on TimeoutException {
      _logger.detail('Graceful kill timed out, force killing...');
      process.kill(ProcessSignal.sigkill);
      try {
        await process.exitCode.timeout(const Duration(seconds: 3));
      } on TimeoutException {
        _logger.detail('Force kill timed out, process may be orphaned');
      }
    }
  }
}

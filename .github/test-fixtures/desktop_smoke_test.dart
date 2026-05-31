import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';

void main() {
  // Test 1: basic widget rendering
  patrolTest('renders widgets on desktop', ($) async {
    await $.pumpWidgetAndSettle(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(title: const Text('Desktop Test')),
          body: const Center(child: Text('Hello Desktop')),
        ),
      ),
    );

    expect($('Desktop Test'), findsOneWidget);
    expect($('Hello Desktop'), findsOneWidget);
  });

  // Test 2: stateful interaction (exercises the relaunch path since
  // PatrolAppService uses one-shot Completers -- each test gets a fresh app)
  patrolTest('handles tap and state change', ($) async {
    await $.pumpWidgetAndSettle(
      MaterialApp(home: const _CounterPage()),
    );

    expect($('Count: 0'), findsOneWidget);
    await $(FloatingActionButton).tap();
    expect($('Count: 1'), findsOneWidget);
    await $(FloatingActionButton).tap();
    expect($('Count: 2'), findsOneWidget);
  });

  // Test 3: verify desktop automator is accessible via $.platform.desktop
  patrolTest('desktop automator is wired', ($) async {
    await $.pumpWidgetAndSettle(
      const MaterialApp(home: Scaffold(body: Text('Automator Check'))),
    );

    expect(DesktopAutomator.isSupported, isTrue);
    expect($.platform.desktop, isA<DesktopAutomator>());
  });
}

class _CounterPage extends StatefulWidget {
  const _CounterPage();

  @override
  State<_CounterPage> createState() => _CounterPageState();
}

class _CounterPageState extends State<_CounterPage> {
  int _count = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(child: Text('Count: $_count')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => setState(() => _count++),
        child: const Icon(Icons.add),
      ),
    );
  }
}

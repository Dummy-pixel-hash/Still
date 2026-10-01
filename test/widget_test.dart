import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:still/src/app.dart';
import 'package:still/src/session/session_manager.dart';
import 'package:still/src/storage/credential_store.dart';

SessionManager _testManager() => SessionManager(
      credentials: MemoryCredentialStore(),
    );

void main() {
  testWidgets('Workspace boots with sessions home', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final manager = _testManager();
    await manager.load();
    await tester.pumpWidget(StillApp(manager: manager));
    await tester.pumpAndSettle();
    expect(find.text('Sessions'), findsOneWidget);
    expect(find.text('New session'), findsOneWidget);
    expect(find.text('No sessions yet.'), findsOneWidget);
    manager.dispose();
  });

  testWidgets('Created session appears as a card', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final manager = _testManager();
    await manager.load();
    await manager.create(
        name: 'Atlas editor', host: 'dev-fra-02', username: 'maya');
    await tester.pumpWidget(StillApp(manager: manager));
    await tester.pumpAndSettle();
    expect(find.text('Atlas editor'), findsOneWidget);
    expect(find.text('maya@dev-fra-02'), findsOneWidget);
    manager.dispose();
  });

  testWidgets('Tapping a card opens the fullscreen terminal',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final manager = _testManager();
    await manager.load();
    await manager.create(
        name: 'Atlas editor', host: 'dev-fra-02', username: 'maya');
    await tester.pumpWidget(StillApp(manager: manager));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Atlas editor'));
    // No pumpAndSettle here: the live terminal cursor blinks forever.
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(seconds: 2));
    // Fullscreen terminal: pill back affordance + auth overlay connect.
    expect(find.text('Workspace'), findsWidgets);
    manager.dispose();
  });

  testWidgets('New-session form creates a card', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final manager = _testManager();
    await manager.load();
    await tester.pumpWidget(StillApp(manager: manager));
    await tester.pumpAndSettle();

    await tester.tap(find.text('New session'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('session-name')), 'Lab shell');
    await tester.enterText(
        find.byKey(const ValueKey('session-host')), 'pve-01.lan');
    await tester.enterText(
        find.byKey(const ValueKey('session-user')), 'root');
    await tester.tap(find.text('Create session'));
    // Create selects the session, landing on the fullscreen terminal
    // (cursor blinks, connect attempt in flight: explicit pumps only).
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Lab shell'), findsWidgets);
    expect(find.text('Workspace'), findsWidgets);
    manager.dispose();
  });

  testWidgets('Settings gear opens local settings', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final manager = _testManager();
    await manager.load();
    await tester.pumpWidget(StillApp(manager: manager));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('TERMINAL'), findsOneWidget);
    expect(find.text('SSH keys'), findsOneWidget);
    manager.dispose();
  });

  testWidgets('Single ungrouped list shows no redundant header',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final manager = _testManager();
    await manager.load();
    await manager.create(
        name: 'Solo', host: 'h1', username: 'u');
    await tester.pumpWidget(StillApp(manager: manager));
    await tester.pumpAndSettle();
    // Serif title only; no second "Sessions" group header.
    expect(find.text('Sessions'), findsOneWidget);
    expect(find.text('Solo'), findsOneWidget);
    manager.dispose();
  });

  testWidgets('Project sessions render under their group header',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final manager = _testManager();
    await manager.load();
    await manager.create(
        name: 'Editor', host: 'h1', username: 'u', project: 'Atlas');
    await manager.create(
        name: 'Shell', host: 'h2', username: 'u');
    await tester.pumpWidget(StillApp(manager: manager));
    await tester.pumpAndSettle();
    expect(find.text('Atlas'), findsOneWidget);
    expect(find.text('Editor'), findsOneWidget);
    expect(find.text('Shell'), findsOneWidget);
    manager.dispose();
  });
}

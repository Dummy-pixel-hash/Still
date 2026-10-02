import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:still/src/app.dart';
import 'package:still/src/session/session_manager.dart';
import 'package:still/src/ssh/ssh_connection.dart';
import 'package:still/src/config/ssh_config.dart';
import 'package:still/src/storage/credential_store.dart';

/// A channel that never completes its output stream, suitable for tests
/// where the connection succeeds but the remote side never sends data.
class _FakeChannel implements SshShellChannel {
  final _stdoutCtrl = StreamController<Uint8List>.broadcast();
  final _doneCompleter = Completer<void>();

  @override
  Stream<Uint8List> get stdout => _stdoutCtrl.stream;

  @override
  void write(Uint8List data) {}

  @override
  void resize(int cols, int rows,
      [int pixelWidth = 0, int pixelHeight = 0]) {}

  @override
  Future<void> get done => _doneCompleter.future;

  @override
  Future<void> close() async {
    if (!_doneCompleter.isCompleted) _doneCompleter.complete();
    await _stdoutCtrl.close();
  }
}

/// A factory that returns a successful fake channel — no network needed.
/// Captures the last [SshConfig] it was called with.
class _FakeSshFactory implements SshConnectionFactory {
  SshConfig? lastConfig;

  @override
  Future<SshShellChannel> openShell(SshConfig config) async {
    lastConfig = config;
    return _FakeChannel();
  }
}

SessionManager _testManager([_FakeSshFactory? factory]) {
  final f = factory ?? _FakeSshFactory();
  return SessionManager(
    credentials: MemoryCredentialStore(),
    sshFactory: f,
  );
}

/// Switches the form's Auth dropdown to SSH key. Uses the dropdown's key
/// so the finder is unambiguous (the word "Password" also appears as the
/// password field's label).
Future<void> _selectKeyAuth(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('session-auth')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('SSH key').last);
  await tester.pumpAndSettle();
}

/// Submits the session form. The button sits at the bottom of a scrollable
/// sheet, so it must be scrolled into the test viewport first — tapping an
/// off-screen widget silently misses.
Future<void> _submitForm(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const ValueKey('session-submit')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('session-submit')));
  await tester.pump();
}

void main() {
  group('workspace', () {
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
      // Fullscreen terminal: pill back affordance + auth overlay.
      expect(find.text('Workspace'), findsWidgets);
      manager.dispose();
    });

    testWidgets('New-session form creates and connects a password session',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final factory = _FakeSshFactory();
      final manager = _testManager(factory);
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
      // Password is required before Create & connect is enabled.
      await tester.enterText(
          find.byKey(const ValueKey('session-password')), 'hunter2');
      await _submitForm(tester);
      // Create & connect: form pops, terminal opens, connect fires.
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Lab shell'), findsWidgets);
      expect(find.text('Workspace'), findsWidgets);
      // The SSH config carried the password through to the factory.
      expect(factory.lastConfig?.password, 'hunter2');
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
      await manager.create(name: 'Solo', host: 'h1', username: 'u');
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
      await manager.create(name: 'Shell', host: 'h2', username: 'u');
      await tester.pumpWidget(StillApp(manager: manager));
      await tester.pumpAndSettle();
      expect(find.text('Atlas'), findsOneWidget);
      expect(find.text('Editor'), findsOneWidget);
      expect(find.text('Shell'), findsOneWidget);
      manager.dispose();
    });
  });

  group('new-session form validation', () {
    testWidgets('Create & connect blocked when password missing',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final manager = _testManager();
      await manager.load();
      await tester.pumpWidget(StillApp(manager: manager));
      await tester.pumpAndSettle();

      await tester.tap(find.text('New session'));
      await tester.pumpAndSettle();

      // Fill host/user but skip password.
      await tester.enterText(
          find.byKey(const ValueKey('session-host')), 'h1');
      await tester.enterText(
          find.byKey(const ValueKey('session-user')), 'u');
      await _submitForm(tester);

      // The form stays open with the validation message.
      expect(find.text('Create & connect'), findsOneWidget);
      expect(find.text('Enter your password to connect.'), findsOneWidget);
      // No session was created.
      expect(manager.sessions, isEmpty);
      manager.dispose();
    });

    testWidgets('Create & connect blocked when port is invalid',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final manager = _testManager();
      await manager.load();
      await tester.pumpWidget(StillApp(manager: manager));
      await tester.pumpAndSettle();

      await tester.tap(find.text('New session'));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byKey(const ValueKey('session-host')), 'h1');
      await tester.enterText(
          find.byKey(const ValueKey('session-user')), 'u');
      await tester.enterText(
          find.byKey(const ValueKey('session-port')), 'not-a-number');
      await tester.enterText(
          find.byKey(const ValueKey('session-password')), 'pw');
      await _submitForm(tester);

      expect(find.text('Port must be a number 1\u201365535.'), findsOneWidget);
      expect(manager.sessions, isEmpty);
      manager.dispose();
    });

    testWidgets('Create & connect blocked when host missing',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final manager = _testManager();
      await manager.load();
      await tester.pumpWidget(StillApp(manager: manager));
      await tester.pumpAndSettle();

      await tester.tap(find.text('New session'));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byKey(const ValueKey('session-user')), 'u');
      await tester.enterText(
          find.byKey(const ValueKey('session-password')), 'pw');
      await _submitForm(tester);

      expect(find.text('Enter a host \u2014 e.g. dev-fra-02.'), findsOneWidget);
      expect(manager.sessions, isEmpty);
      manager.dispose();
    });
  });

  group('new-session key auth flow', () {
    testWidgets('Key auth shows PEM field for Ask every time',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final manager = _testManager();
      await manager.load();
      await tester.pumpWidget(StillApp(manager: manager));
      await tester.pumpAndSettle();

      await tester.tap(find.text('New session'));
      await tester.pumpAndSettle();

      // Switch to SSH key auth.
      await _selectKeyAuth(tester);

      // PEM field should appear for "Ask every time".
      expect(find.byKey(const ValueKey('session-key-pem')), findsOneWidget);
      // "Ask every time" helper copy visible.
      expect(find.textContaining('Ask every time'), findsWidgets);
      manager.dispose();
    });

    testWidgets('Create & connect blocked when PEM missing for Ask every time',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final manager = _testManager();
      await manager.load();
      await tester.pumpWidget(StillApp(manager: manager));
      await tester.pumpAndSettle();

      await tester.tap(find.text('New session'));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byKey(const ValueKey('session-host')), 'h1');
      await tester.enterText(
          find.byKey(const ValueKey('session-user')), 'u');
      // Switch to SSH key auth.
      await _selectKeyAuth(tester);

      // Submit without pasting a key.
      await _submitForm(tester);

      expect(
          find.text(
              'Paste your private key to connect, or pick a saved key.'),
          findsOneWidget);
      expect(manager.sessions, isEmpty);
      manager.dispose();
    });

    testWidgets('Saved key option appears when keys exist', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final factory = _FakeSshFactory();
      final manager = _testManager(factory);
      await manager.load();

      // Import a saved key.
      await manager.keys.add(name: 'laptop', pem: 'PEM-LAPTOP');

      await tester.pumpWidget(StillApp(manager: manager));
      await tester.pumpAndSettle();

      await tester.tap(find.text('New session'));
      await tester.pumpAndSettle();

      await _selectKeyAuth(tester);

      // Open the key-source dropdown: saved keys appear as options there.
      await tester.tap(find.byKey(const ValueKey('session-key-source')));
      await tester.pumpAndSettle();
      expect(find.text('laptop'), findsOneWidget);

      manager.dispose();
    });
  });
}

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:still/src/app.dart';
import 'package:still/src/session/session_manager.dart';
import 'package:still/src/ssh/ssh_connection.dart';
import 'package:still/src/config/ssh_config.dart';
import 'package:still/src/session/still_session.dart';
import 'package:still/src/storage/credential_store.dart';

/// Milestone 2: discoverable session actions + honest disconnect semantics.
///
/// Covers: visible overflow affordance, Open/Edit/Remove actions,
/// empty-state New Session CTA, per-project `+`, disconnect from the
/// terminal, detached representation afterwards, and corrected
/// persistence/remove copy. Milestone 1 SSH/auth behavior is untouched.

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

class _FakeSshFactory implements SshConnectionFactory {
  @override
  Future<SshShellChannel> openShell(SshConfig config) async =>
      _FakeChannel();
}

SessionManager _testManager() => SessionManager(
      credentials: MemoryCredentialStore(),
      sshFactory: _FakeSshFactory(),
    );

Future<StillSession> _createSession(SessionManager manager,
    {String name = 'Atlas editor',
    String host = 'dev-fra-02',
    String project = ''}) {
  return manager.create(
      name: name, host: host, username: 'maya', project: project);
}

/// Opens the card's action sheet via the visible overflow button and
/// settles (workspace has no blinking cursor, so settling is safe).
Future<void> _openActions(WidgetTester tester, String sessionId) async {
  await tester.tap(find.byKey(ValueKey('session-overflow-$sessionId')));
  await tester.pumpAndSettle();
}

void main() {
  group('session card actions', () {
    testWidgets('every card shows a visible overflow affordance',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final manager = _testManager();
      await manager.load();
      await _createSession(manager, name: 'One');
      await _createSession(manager, name: 'Two');
      await tester.pumpWidget(StillApp(manager: manager));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Session actions'), findsNWidgets(2));
      manager.dispose();
    });

    testWidgets('overflow opens Open/Edit/Remove without leaving workspace',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final manager = _testManager();
      await manager.load();
      final s = await _createSession(manager);
      await tester.pumpWidget(StillApp(manager: manager));
      await tester.pumpAndSettle();

      await _openActions(tester, s.id);
      expect(find.text('Open'), findsOneWidget);
      expect(find.text('Edit'), findsOneWidget);
      expect(find.text('Remove'), findsOneWidget);
      // The sheet opened over the workspace — no navigation happened.
      expect(find.text('Sessions'), findsWidgets);
      manager.dispose();
    });

    testWidgets('Open action opens the terminal', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final manager = _testManager();
      await manager.load();
      final s = await _createSession(manager);
      await tester.pumpWidget(StillApp(manager: manager));
      await tester.pumpAndSettle();

      await _openActions(tester, s.id);
      await tester.tap(find.text('Open'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Workspace'), findsWidgets);
      manager.dispose();
    });

    testWidgets('Edit action opens the metadata form', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final manager = _testManager();
      await manager.load();
      final s = await _createSession(manager);
      await tester.pumpWidget(StillApp(manager: manager));
      await tester.pumpAndSettle();

      await _openActions(tester, s.id);
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      expect(find.text('Edit session'), findsOneWidget);

      // Saving unchanged metadata closes the form; the card stays.
      await tester.ensureVisible(find.text('Save changes'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      expect(find.text('Atlas editor'), findsOneWidget);
      manager.dispose();
    });

    testWidgets('Remove asks first, uses honest copy, removes the card',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final manager = _testManager();
      await manager.load();
      final s = await _createSession(manager);
      await tester.pumpWidget(StillApp(manager: manager));
      await tester.pumpAndSettle();

      await _openActions(tester, s.id);
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();

      expect(find.text('Remove session?'), findsOneWidget);
      // No promise of reattaching from a new session anymore.
      expect(find.textContaining('reattached from a new session'),
          findsNothing);
      expect(
          find.textContaining('can’t be reattached afterwards'),
          findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'Remove'));
      await tester.pumpAndSettle();
      expect(manager.sessions, isEmpty);
      expect(find.text('Atlas editor'), findsNothing);
      manager.dispose();
    });

    testWidgets('long-press still opens the same sheet', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final manager = _testManager();
      await manager.load();
      await _createSession(manager);
      await tester.pumpWidget(StillApp(manager: manager));
      await tester.pumpAndSettle();

      await tester.longPress(find.text('Atlas editor'));
      await tester.pumpAndSettle();
      expect(find.text('Open'), findsOneWidget);
      expect(find.text('Edit'), findsOneWidget);
      expect(find.text('Remove'), findsOneWidget);
      manager.dispose();
    });
  });

  group('empty state', () {
    testWidgets('empty state has a New Session CTA opening the form',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final manager = _testManager();
      await manager.load();
      await tester.pumpWidget(StillApp(manager: manager));
      await tester.pumpAndSettle();

      expect(find.text('No sessions yet.'), findsOneWidget);
      expect(find.byKey(const ValueKey('empty-state-new-session')),
          findsOneWidget);

      await tester
          .tap(find.byKey(const ValueKey('empty-state-new-session')));
      await tester.pumpAndSettle();
      expect(find.text('New session'), findsWidgets);
      manager.dispose();
    });
  });

  group('project quick-add', () {
    testWidgets('project header + prefills the project field',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final manager = _testManager();
      await manager.load();
      await _createSession(manager, name: 'Editor', project: 'Atlas');
      await _createSession(manager, name: 'Shell');
      await tester.pumpWidget(StillApp(manager: manager));
      await tester.pumpAndSettle();

      expect(find.text('Atlas'), findsOneWidget);
      expect(find.byKey(const ValueKey('project-add-Atlas')),
          findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('project-add-Atlas')));
      await tester.pumpAndSettle();
      final field = tester.widget<TextFormField>(
          find.byKey(const ValueKey('session-project')));
      expect(field.controller?.text, 'Atlas');
      manager.dispose();
    });
  });

  group('terminal disconnect', () {
    testWidgets(
        'disconnect closes transport, keeps the card, detaches the session',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final manager = _testManager();
      await manager.load();
      final s = await _createSession(manager);
      // Stage a secret so opening the card auto-connects (Milestone 1).
      await manager.stageSecret(s, 'hunter2');
      await tester.pumpWidget(StillApp(manager: manager));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Atlas editor'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(seconds: 1));
      expect(manager.connectionOf(s.id), TransportState.connected);

      // Disconnect is exposed in the terminal chrome, next to Workspace.
      expect(find.byKey(const ValueKey('terminal-disconnect')),
          findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('terminal-disconnect')));
      // Teardown awaits stream-subscription cancels whose completion
      // needs real event-loop turns; the widget binding starves those,
      // so wait on a real clock (production and unit tests use one).
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 500));
      });
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));

      expect(manager.connectionOf(s.id), TransportState.disconnected);
      // The card is not deleted; the session reads as detached.
      expect(manager.sessions.map((e) => e.id), contains(s.id));
      expect(manager.sessionStateOf(s.id), SessionState.detached);
      // Reattach path is offered in place.
      expect(find.text('Reattach'), findsOneWidget);

      // Back in the workspace the card still stands, marked detached.
      await tester.tap(find.text('Workspace').first);
      await tester.pumpAndSettle();
      expect(find.text('Atlas editor'), findsOneWidget);
      expect(find.text('Detached'), findsOneWidget);
      manager.dispose();
    });

    testWidgets('overlay explains leave-vs-disconnect honestly',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final manager = _testManager();
      await manager.load();
      // No secret staged: the calm auth overlay shows the footnote.
      await _createSession(manager);
      await tester.pumpWidget(StillApp(manager: manager));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Atlas editor'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.textContaining('leaves the connection open'),
          findsOneWidget);
      expect(
          find.textContaining('the remote runtime keeps running'),
          findsOneWidget);
      manager.dispose();
    });
  });
}

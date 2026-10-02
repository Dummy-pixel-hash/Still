import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:still/src/app.dart';
import 'package:still/src/session/session_manager.dart';
import 'package:still/src/ssh/ssh_connection.dart';
import 'package:still/src/config/ssh_config.dart';
import 'package:still/src/storage/credential_store.dart';

/// Milestone 4: Still visual/spatial experience.
///
/// Covers the changed interactions only: Ctrl+K search focus, the
/// Still sort control, the card-origin morph (workspace stays mounted
/// behind the terminal), workspace state preservation across the trip,
/// and desktop sheet width. All 118 prior tests are preserved untouched.

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

void main() {
  group('search + sort controls', () {
    testWidgets('Ctrl+K focuses the search field', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final manager = _testManager();
      await manager.load();
      await tester.pumpWidget(StillApp(manager: manager));
      await tester.pumpAndSettle();

      final field = find.byKey(const ValueKey('workspace-search'));
      expect(field, findsOneWidget);
      expect(
          tester
              .widget<TextField>(field)
              .focusNode
              ?.hasFocus,
          isFalse);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
      await tester.pump();

      expect(
          tester
              .widget<TextField>(field)
              .focusNode
              ?.hasFocus,
          isTrue);
      expect(find.text('Ctrl K'), findsOneWidget);
      manager.dispose();
    });

    testWidgets('search still filters the card list', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final manager = _testManager();
      await manager.load();
      final a = await manager.create(
          name: 'Atlas', host: 'h1', username: 'u');
      await manager.create(name: 'Shell', host: 'h2', username: 'u');
      await tester.pumpWidget(StillApp(manager: manager));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byKey(const ValueKey('workspace-search')), 'Atlas');
      await tester.pumpAndSettle();
      // The card itself (keyed by session id — the field text also
      // contains the query, so plain text finders are ambiguous here).
      expect(find.byKey(ValueKey('session-overflow-${a.id}')),
          findsOneWidget);
      expect(find.text('Shell'), findsNothing);
      manager.dispose();
    });

    testWidgets('Still sort control reorders Name A-Z', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final manager = _testManager();
      await manager.load();
      await manager.create(name: 'Zulu', host: 'h1', username: 'u');
      await manager.create(name: 'Alpha', host: 'h2', username: 'u');
      await tester.pumpWidget(StillApp(manager: manager));
      await tester.pumpAndSettle();

      // Manual order: creation order, left to right on this grid.
      var zuluDx = tester.getTopLeft(find.text('Zulu')).dx;
      var alphaDx = tester.getTopLeft(find.text('Alpha')).dx;
      expect(zuluDx, lessThan(alphaDx));

      await tester.tap(find.text('Manual order'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Name A–Z'));
      await tester.pumpAndSettle();

      zuluDx = tester.getTopLeft(find.text('Zulu')).dx;
      alphaDx = tester.getTopLeft(find.text('Alpha')).dx;
      expect(alphaDx, lessThan(zuluDx));
      manager.dispose();
    });
  });

  group('card-origin morph', () {
    testWidgets('workspace stays mounted behind the terminal',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final manager = _testManager();
      await manager.load();
      final s = await manager.create(
          name: 'Atlas', host: 'h1', username: 'u');
      await tester.pumpWidget(StillApp(manager: manager));
      await tester.pumpAndSettle();

      // Tap the card surface itself to exercise the morph origin path.
      await tester.tap(find.byKey(ValueKey(s.id)));
      // Mid-morph: the workspace is still in the tree under the
      // expanding terminal surface.
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Sessions'), findsOneWidget);
      expect(find.text('Workspace'), findsWidgets);

      // Settled: terminal open, workspace preserved behind it. The morph
      // is driven per-frame, so step it generously rather than assuming
      // a fixed fake-time budget.
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('Atlas'), findsWidgets);
      expect(find.text('Sessions'), findsOneWidget);

      // Back via the chrome pill: the morph reverses and the terminal
      // unmounts.
      await tester.tap(find.text('Workspace').last);
      await tester.pumpAndSettle();
      expect(manager.selected, isNull);
      expect(find.text('Workspace'), findsNothing);
      expect(find.text('Atlas'), findsOneWidget);
      manager.dispose();
    });

    testWidgets('workspace search state survives the terminal trip',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final manager = _testManager();
      await manager.load();
      final a = await manager.create(
          name: 'Atlas editor', host: 'h1', username: 'u');
      await manager.create(name: 'Shell', host: 'h2', username: 'u');
      await tester.pumpWidget(StillApp(manager: manager));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byKey(const ValueKey('workspace-search')), 'Atlas');
      await tester.pumpAndSettle();
      expect(find.text('Shell'), findsNothing);

      await tester.tap(find.byKey(ValueKey(a.id)));
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.tap(find.text('Workspace').last);
      await tester.pumpAndSettle();

      // The query (and its filter) survived: the workspace never
      // unmounted, unlike the old screen-swap behavior.
      expect(find.text('Atlas editor'), findsOneWidget);
      expect(find.text('Shell'), findsNothing);
      manager.dispose();
    });
  });

  group('desktop sheets', () {
    testWidgets('product sheets are width-constrained on desktop',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final manager = _testManager();
      await manager.load();
      await tester.pumpWidget(StillApp(manager: manager));
      await tester.pumpAndSettle();

      await tester.tap(find.text('New session'));
      await tester.pumpAndSettle();
      expect(find.text('New session'), findsWidgets);

      // 800pt-wide surface: the sheet frame caps at 480pt, centered.
      final frame = find.byKey(const ValueKey('still-sheet-frame'));
      expect(frame, findsOneWidget);
      expect(tester.getSize(frame).width, 480);
      manager.dispose();
    });
  });
}

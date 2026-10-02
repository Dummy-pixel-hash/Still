import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:still/src/app.dart';
import 'package:still/src/config/ssh_config.dart';
import 'package:still/src/session/connection_errors.dart';
import 'package:still/src/session/remote_session_controller.dart';
import 'package:still/src/session/session_manager.dart';
import 'package:still/src/session/session_validation.dart';
import 'package:still/src/session/still_session.dart';
import 'package:still/src/ssh/ssh_connection.dart';
import 'package:still/src/storage/credential_store.dart';
import 'package:still/src/terminal/terminal_backend.dart';
import 'package:still/src/tmux/tmux.dart';

/// Milestone 3: implied-but-unwired behavior made real.
///
/// Covers: saved-key passphrases, working directory end to end,
/// SessionKind launch commands, validation (port / SshConfig.isValid /
/// dangling keyId), and host-key disclosure copy.

class _Channel implements SshShellChannel {
  final stdoutCtrl = StreamController<Uint8List>.broadcast();
  final doneCompleter = Completer<void>();

  @override
  Stream<Uint8List> get stdout => stdoutCtrl.stream;

  @override
  void write(Uint8List data) {}

  @override
  void resize(int cols, int rows,
      [int pixelWidth = 0, int pixelHeight = 0]) {}

  @override
  Future<void> get done => doneCompleter.future;

  @override
  Future<void> close() async => stdoutCtrl.close();
}

class _Factory implements SshConnectionFactory {
  final List<SshConfig> seen = [];

  @override
  Future<SshShellChannel> openShell(SshConfig config) async {
    seen.add(config);
    return _Channel();
  }
}

SessionManager _manager(_Factory factory, MemoryCredentialStore creds) =>
    SessionManager(credentials: creds, sshFactory: factory);

Future<void> _flush() =>
    Future<void>.delayed(const Duration(milliseconds: 50));

// --- controller-level fakes (capture bytes written to the shell) ---

class _FakeTerminal implements TerminalBackend {
  final out = StreamController<String>.broadcast();
  final resizes = StreamController<TerminalSize>.broadcast();
  @override
  int cols = 80;
  @override
  int rows = 24;

  @override
  void feed(String data) {}

  @override
  Stream<String> get output => out.stream;

  @override
  Stream<TerminalSize> get onResize => resizes.stream;

  @override
  void resize(int c, int r) {
    cols = c;
    rows = r;
  }

  @override
  void dispose() {
    out.close();
    resizes.close();
  }
}

class _WireChannel implements SshShellChannel {
  final written = <String>[];
  final stdoutCtrl = StreamController<Uint8List>.broadcast();
  final doneCtrl = Completer<void>();

  @override
  Stream<Uint8List> get stdout => stdoutCtrl.stream;

  @override
  void write(Uint8List data) =>
      written.add(String.fromCharCodes(data));

  @override
  void resize(int cols, int rows,
      [int pixelWidth = 0, int pixelHeight = 0]) {}

  @override
  Future<void> get done => doneCtrl.future;

  @override
  Future<void> close() async => stdoutCtrl.close();
}

class _WireFactory implements SshConnectionFactory {
  final List<_WireChannel> channels = [];
  @override
  Future<SshShellChannel> openShell(SshConfig config) async {
    final c = _WireChannel();
    channels.add(c);
    return c;
  }
}

void main() {
  group('saved-key passphrase', () {
    test('passphrase-protected saved key reaches the transport', () async {
      SharedPreferences.setMockInitialValues({});
      final creds = MemoryCredentialStore();
      final factory = _Factory();
      final manager = _manager(factory, creds);
      await manager.load();

      final key = await manager.keys.add(
          name: 'laptop', pem: 'PEM-LOCKED', passphrase: 's3cr3t');
      final s = await manager.create(
        name: 'S',
        host: 'h1',
        username: 'u',
        authKind: SshAuthKind.privateKey,
        keyId: key.id,
      );
      await manager.connect(s);
      await _flush();
      expect(factory.seen.single.privateKeyPem, 'PEM-LOCKED');
      expect(factory.seen.single.privateKeyPassphrase, 's3cr3t');
      expect(manager.connectionOf(s.id), TransportState.connected);
      manager.dispose();
    });

    test('saved key without passphrase sends a null passphrase', () async {
      SharedPreferences.setMockInitialValues({});
      final creds = MemoryCredentialStore();
      final factory = _Factory();
      final manager = _manager(factory, creds);
      await manager.load();

      final key = await manager.keys.add(name: 'plain', pem: 'PEM-PLAIN');
      final s = await manager.create(
        name: 'S',
        host: 'h1',
        username: 'u',
        authKind: SshAuthKind.privateKey,
        keyId: key.id,
      );
      await manager.connect(s);
      await _flush();
      expect(factory.seen.single.privateKeyPem, 'PEM-PLAIN');
      expect(factory.seen.single.privateKeyPassphrase, isNull);
      manager.dispose();
    });

    test('one-off pasted key and password sessions send no passphrase',
        () async {
      SharedPreferences.setMockInitialValues({});
      final creds = MemoryCredentialStore();
      final factory = _Factory();
      final manager = _manager(factory, creds);
      await manager.load();

      final k = await manager.create(
        name: 'K',
        host: 'h1',
        username: 'u',
        authKind: SshAuthKind.privateKey,
      );
      await manager.stageSecret(k, 'PEM-ONEOFF');
      await manager.connect(k);
      await _flush();
      expect(factory.seen.single.privateKeyPassphrase, isNull);

      final p = await manager.create(
          name: 'P', host: 'h1', username: 'u');
      await manager.connect(p, secret: 'pw');
      await _flush();
      expect(factory.seen.last.privateKeyPassphrase, isNull);
      manager.dispose();
    });

    test('key material (PEM + passphrase) stays out of prefs', () async {
      SharedPreferences.setMockInitialValues({});
      final creds = MemoryCredentialStore();
      final factory = _Factory();
      final manager = _manager(factory, creds);
      await manager.load();

      final key = await manager.keys.add(
          name: 'laptop',
          pem: 'PEM-SUPER-SECRET',
          passphrase: 'PASSPHRASE-SUPER-SECRET');
      final s = await manager.create(
        name: 'S',
        host: 'h1',
        username: 'u',
        authKind: SshAuthKind.privateKey,
        keyId: key.id,
      );
      await manager.connect(s);
      await _flush();

      final prefs = await SharedPreferences.getInstance();
      for (final k in prefs.getKeys()) {
        final v = prefs.getString(k) ?? '';
        expect(v, isNot(contains('PEM-SUPER-SECRET')));
        expect(v, isNot(contains('PASSPHRASE-SUPER-SECRET')));
      }
      manager.dispose();
    });
  });

  group('working directory', () {
    test('workdir flows from the session into the connection config',
        () async {
      SharedPreferences.setMockInitialValues({});
      final creds = MemoryCredentialStore();
      final factory = _Factory();
      final manager = _manager(factory, creds);
      await manager.load();

      final s = await manager.create(
        name: 'S',
        host: 'h1',
        username: 'u',
        workdir: '/home/maya/atlas',
      );
      expect(s.workdir, '/home/maya/atlas');
      await manager.stageSecret(s, 'pw');
      await manager.connect(s);
      await _flush();
      expect(factory.seen.single.workdir, '/home/maya/atlas');
      manager.dispose();
    });

    test('empty workdir normalizes to the home marker', () async {
      SharedPreferences.setMockInitialValues({});
      final manager = _manager(_Factory(), MemoryCredentialStore());
      await manager.load();
      final s = await manager.create(
          name: 'S', host: 'h1', username: 'u', workdir: '  ');
      expect(s.workdir, '~');
      manager.dispose();
    });

    test('start directory becomes tmux -c on the attach command', () {
      expect(
        const TmuxPlan(sessionName: 's-1').attachCommand(
            startDirectory: '/home/maya/atlas'),
        'tmux -u new-session -A -s s-1 -c \'/home/maya/atlas\''
        ' -x 80 -y 24\n',
      );
    });

    test('empty and home workdirs omit -c (login default)', () {
      const base = 'tmux -u new-session -A -s s-1 -x 80 -y 24\n';
      expect(const TmuxPlan(sessionName: 's-1').attachCommand(), base);
      expect(
        const TmuxPlan(sessionName: 's-1')
            .attachCommand(startDirectory: ''),
        base,
      );
      expect(
        const TmuxPlan(sessionName: 's-1')
            .attachCommand(startDirectory: '~'),
        base,
      );
    });

    test('shell quoting escapes quotes, preserves leading ~', () {
      expect(TmuxPlan.shQuote("a'b"), "'a'\\''b'");
      expect(TmuxPlan.shQuotePath('~/p x'), "~'/p x'");
      expect(TmuxPlan.shQuotePath('/a b'), "'/a b'");
    });

    test('attach on the wire carries directory and creation command',
        () async {
      final term = _FakeTerminal();
      final factory = _WireFactory();
      final ctrl =
          RemoteSessionController(terminal: term, sshFactory: factory);
      await ctrl.connect(const SshConfig(
        host: 'h1',
        username: 'u',
        tmuxSession: 's-1',
        workdir: '/home/maya/atlas',
        startCommand: 'nvim',
      ));
      expect(
        factory.channels.single.written.join(),
        'tmux -u new-session -A -s s-1 -c \'/home/maya/atlas\''
        ' nvim -x 80 -y 24\n',
      );
      await ctrl.disconnect();
      term.dispose();
    });
  });

  group('session kind launches', () {
    test('kinds map to creation commands; shell means default', () {
      expect(startCommandFor(SessionKind.shell), isNull);
      expect(startCommandFor(SessionKind.agent), 'claude');
      expect(startCommandFor(SessionKind.editor), 'nvim');
      expect(startCommandFor(SessionKind.git), 'lazygit');
      expect(startCommandFor(SessionKind.monitor), 'btop');
      expect(startCommandFor(SessionKind.logs), 'tail -f');
    });

    test('kind flows session -> config; shell sends no command', () async {
      SharedPreferences.setMockInitialValues({});
      final creds = MemoryCredentialStore();
      final factory = _Factory();
      final manager = _manager(factory, creds);
      await manager.load();

      final e = await manager.create(
          name: 'E', host: 'h1', username: 'u', kind: SessionKind.editor);
      await manager.stageSecret(e, 'pw');
      await manager.connect(e);
      await _flush();
      expect(factory.seen.single.startCommand, 'nvim');

      final sh = await manager.create(
          name: 'Sh', host: 'h1', username: 'u', kind: SessionKind.shell);
      await manager.stageSecret(sh, 'pw');
      await manager.connect(sh);
      await _flush();
      expect(factory.seen.last.startCommand, '');
      manager.dispose();
    });

    test('creation command is creation-only on the attach line', () {
      expect(
        const TmuxPlan(sessionName: 's-1')
            .attachCommand(startCommand: 'tail -f'),
        'tmux -u new-session -A -s s-1 tail -f -x 80 -y 24\n',
      );
    });
  });

  group('connection config validation', () {
    test('connect with an empty host refuses without dialing', () async {
      SharedPreferences.setMockInitialValues({});
      final creds = MemoryCredentialStore();
      final factory = _Factory();
      final manager = _manager(factory, creds);
      await manager.load();

      final s = await manager.create(
          name: 'S', host: '', username: 'u');
      await manager.stageSecret(s, 'pw');
      await expectLater(() => manager.connect(s), throwsStateError);
      await _flush();
      expect(factory.seen, isEmpty);
      expect(manager.errorOf(s.id), invalidSessionConfigMessage());
      expect(manager.connectionOf(s.id), TransportState.error);
      manager.dispose();
    });

    test('connect with key auth and no key refuses without dialing',
        () async {
      SharedPreferences.setMockInitialValues({});
      final creds = MemoryCredentialStore();
      final factory = _Factory();
      final manager = _manager(factory, creds);
      await manager.load();

      final s = await manager.create(
        name: 'S',
        host: 'h1',
        username: 'u',
        authKind: SshAuthKind.privateKey,
      );
      await expectLater(() => manager.connect(s), throwsStateError);
      await _flush();
      expect(factory.seen, isEmpty);
      manager.dispose();
    });

    test('create and update reject out-of-range ports explicitly', () async {
      SharedPreferences.setMockInitialValues({});
      final manager = _manager(_Factory(), MemoryCredentialStore());
      await manager.load();

      await expectLater(
        () => manager.create(
            name: 'S', host: 'h1', username: 'u', port: 0),
        throwsArgumentError,
      );
      await expectLater(
        () => manager.create(
            name: 'S', host: 'h1', username: 'u', port: 65536),
        throwsArgumentError,
      );
      final s = await manager.create(
          name: 'S', host: 'h1', username: 'u', port: 22);
      await expectLater(
          () => manager.update(s.id, port: 99999), throwsArgumentError);
      expect(manager.sessions.single.port, 22);
      await manager.update(s.id, port: 2222);
      expect(manager.sessions.single.port, 2222);
      manager.dispose();
    });

    test('port field validation rejects out-of-range numbers', () {
      expect(validateSessionPort('99999'), isNotNull);
      expect(validateSessionPort('0'), isNotNull);
      expect(tryParseSessionPort('99999'), isNull);
      expect(tryParseSessionPort('22'), 22);
    });
  });

  group('launch form + disclosure (widget)', () {
    testWidgets('new-session form stores the workdir and connects with it',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final factory = _Factory();
      final manager = _manager(factory, MemoryCredentialStore());
      await manager.load();
      await tester.pumpWidget(StillApp(manager: manager));
      await tester.pumpAndSettle();

      await tester.tap(find.text('New session'));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byKey(const ValueKey('session-name')), 'Atlas');
      await tester.enterText(
          find.byKey(const ValueKey('session-host')), 'h1');
      await tester.enterText(
          find.byKey(const ValueKey('session-user')), 'u');
      await tester.enterText(
          find.byKey(const ValueKey('session-password')), 'pw');
      expect(find.byKey(const ValueKey('session-workdir')), findsOneWidget);
      await tester.enterText(
          find.byKey(const ValueKey('session-workdir')),
          '/home/maya/atlas');
      await tester.ensureVisible(
          find.byKey(const ValueKey('session-submit')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('session-submit')));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(seconds: 1));

      expect(manager.sessions.single.workdir, '/home/maya/atlas');
      expect(factory.seen.single.workdir, '/home/maya/atlas');
      manager.dispose();
    });

    testWidgets('edit form shows the workdir and saves changes',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final manager = _manager(_Factory(), MemoryCredentialStore());
      await manager.load();
      final s = await manager.create(
          name: 'Atlas',
          host: 'h1',
          username: 'u',
          workdir: '/before');
      await tester.pumpWidget(StillApp(manager: manager));
      await tester.pumpAndSettle();

      await tester
          .tap(find.byKey(ValueKey('session-overflow-${s.id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();

      final field = tester.widget<TextFormField>(
          find.byKey(const ValueKey('session-workdir')));
      expect(field.controller?.text, '/before');
      await tester.enterText(
          find.byKey(const ValueKey('session-workdir')), '/after');
      await tester.ensureVisible(find.text('Save changes'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      expect(manager.sessions.single.workdir, '/after');
      manager.dispose();
    });

    testWidgets(
        'dangling saved key warns in edit; saving clears the reference',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final manager = _manager(_Factory(), MemoryCredentialStore());
      await manager.load();
      final key =
          await manager.keys.add(name: 'laptop', pem: 'PEM-X');
      final s = await manager.create(
        name: 'Keyed',
        host: 'h1',
        username: 'u',
        authKind: SshAuthKind.privateKey,
        keyId: key.id,
      );
      await tester.pumpWidget(StillApp(manager: manager));
      await tester.pumpAndSettle();

      await manager.keys.remove(key.id);
      await tester.pumpAndSettle();

      await tester
          .tap(find.byKey(ValueKey('session-overflow-${s.id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();

      expect(find.textContaining('That saved key is gone'), findsOneWidget);
      await tester.ensureVisible(find.text('Save changes'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      expect(manager.sessions.single.keyId, isNull);
      manager.dispose();
    });

    testWidgets('terminal overlay names the missing saved key',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final manager = _manager(_Factory(), MemoryCredentialStore());
      await manager.load();
      final key =
          await manager.keys.add(name: 'laptop', pem: 'PEM-X');
      await manager.create(
        name: 'Keyed',
        host: 'h1',
        username: 'u',
        authKind: SshAuthKind.privateKey,
        keyId: key.id,
      );
      await manager.keys.remove(key.id);
      await tester.pumpWidget(StillApp(manager: manager));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Keyed'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.textContaining('That saved key is gone'), findsOneWidget);
      manager.dispose();
    });

    testWidgets('host-key disclosure is shown in the form and overlay',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final manager = _manager(_Factory(), MemoryCredentialStore());
      await manager.load();
      await tester.pumpWidget(StillApp(manager: manager));
      await tester.pumpAndSettle();

      await tester.tap(find.text('New session'));
      await tester.pumpAndSettle();
      expect(find.textContaining('isn’t verified'), findsOneWidget);
      // Dismiss the sheet via the scrim; pageBack has no back button here.
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      await manager.create(name: 'Plain', host: 'h1', username: 'u');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Plain'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.textContaining('isn’t verified'), findsOneWidget);
      manager.dispose();
    });

    testWidgets('out-of-range port is blocked at field level',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final manager = _manager(_Factory(), MemoryCredentialStore());
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
          find.byKey(const ValueKey('session-password')), 'pw');
      await tester.enterText(
          find.byKey(const ValueKey('session-port')), '99999');
      await tester.ensureVisible(
          find.byKey(const ValueKey('session-submit')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('session-submit')));
      await tester.pumpAndSettle();

      expect(find.text('Port must be a number 1\u201365535.'),
          findsOneWidget);
      expect(manager.sessions, isEmpty);
      manager.dispose();
    });
  });
}

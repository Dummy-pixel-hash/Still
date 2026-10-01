import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:still/src/config/ssh_config.dart';
import 'package:still/src/session/connection_errors.dart';
import 'package:still/src/session/session_manager.dart';
import 'package:still/src/session/still_session.dart';
import 'package:still/src/ssh/ssh_connection.dart';
import 'package:still/src/storage/credential_store.dart';

class _Channel implements SshShellChannel {
  final stdoutCtrl = StreamController<Uint8List>.broadcast();
  final Completer<void> _doneCompleter = Completer<void>();

  @override
  Future<void> get done => _doneCompleter.future;

  @override
  Stream<Uint8List> get stdout => stdoutCtrl.stream;

  @override
  void write(Uint8List data) {}

  @override
  void resize(int cols, int rows,
      [int pixelWidth = 0, int pixelHeight = 0]) {}

  @override
  Future<void> close() async {
    await stdoutCtrl.close();
  }

  void dropTransport() {
    if (!_doneCompleter.isCompleted) _doneCompleter.complete();
  }
}

class _Factory implements SshConnectionFactory {
  _Factory({this.throwOnOpen});
  final Object? throwOnOpen;
  final List<SshConfig> seen = [];
  final List<_Channel> channels = [];

  @override
  Future<SshShellChannel> openShell(SshConfig config) async {
    if (throwOnOpen != null) throw throwOnOpen!;
    seen.add(config);
    final channel = _Channel();
    channels.add(channel);
    return channel;
  }
}

SessionManager _manager(_Factory factory) => SessionManager(
      credentials: MemoryCredentialStore(),
      sshFactory: factory,
    );

Future<void> _flush() =>
    Future<void>.delayed(const Duration(milliseconds: 50));

void main() {
  group('friendly errors', () {
    test('auth failure', () {
      expect(
        friendlyConnectionError(
            'SSHAuthFailError: unable to authenticate'),
        contains('Wrong password'),
      );
    });

    test('connection refused', () {
      expect(
        friendlyConnectionError(
            const SocketException('Connection refused', osError: null)),
        contains('refused SSH'),
      );
    });

    test('unreachable / timeout', () {
      expect(
        friendlyConnectionError(
            TimeoutException('connect', const Duration(seconds: 5))),
        contains('reach'),
      );
      expect(
        friendlyConnectionError(
            const SocketException('Failed host lookup')),
        contains('hostname'),
      );
    });

    test('unknown falls back to generic', () {
      expect(friendlyConnectionError('weird: xyz'), contains('try again'));
    });
  });

  group('sizing', () {
    test('connect + reattach use the live view size, not 80x24', () async {
      SharedPreferences.setMockInitialValues({});
      final factory = _Factory();
      final manager = _manager(factory);
      await manager.load();
      final s = await manager.create(
          name: 'Atlas', host: 'h1', username: 'u');

      manager.open(s.id).backend.resize(120, 40);
      await manager.connect(s, secret: 'pw');
      await _flush();
      expect(factory.seen.single.cols, 120);
      expect(factory.seen.single.rows, 40);
      expect(factory.seen.single.tmuxSession, s.tmuxSession);

      await manager.disconnect(s.id);
      await _flush();
      await manager.reconnect(s.id);
      await _flush();
      expect(factory.seen.last.cols, 120);
      expect(factory.seen.last.rows, 40);
      manager.dispose();
    });
  });

  group('lifecycle', () {
    test('auth failure surfaces error state, stays recoverable',
        () async {
      SharedPreferences.setMockInitialValues({});
      final factory = _Factory(
          throwOnOpen:
              'SSHAuthFailError: unable to authenticate with password');
      final manager = _manager(factory);
      await manager.load();
      final s = await manager.create(
          name: 'Atlas', host: 'h1', username: 'u');

      await expectLater(
          () => manager.connect(s, secret: 'wrong'), throwsA(anything));
      await _flush();
      expect(manager.connectionOf(s.id), TransportState.error);
      expect(manager.errorOf(s.id), contains('Wrong password'));
      // Not stuck: a later attempt is still possible.
      expect(manager.sessionStateOf(s.id), SessionState.unknown);
      manager.dispose();
    });

    test('unexpected transport drop -> disconnected, never fake-live',
        () async {
      SharedPreferences.setMockInitialValues({});
      final factory = _Factory();
      final manager = _manager(factory);
      await manager.load();
      final s = await manager.create(
          name: 'Atlas', host: 'h1', username: 'u');
      await manager.connect(s, secret: 'pw');
      await _flush();
      expect(manager.connectionOf(s.id), TransportState.connected);

      factory.channels.single.dropTransport();
      await _flush();
      await _flush();
      expect(
          manager.connectionOf(s.id), TransportState.disconnected);
      expect(manager.runtimeOf(s.id), RuntimeState.unknown);
      // Remote survives the drop: resumable, not destroyed.
      expect(manager.sessionStateOf(s.id), SessionState.detached);
      manager.dispose();
    });

    test('repeated connect/disconnect cycles stay consistent', () async {
      SharedPreferences.setMockInitialValues({});
      final factory = _Factory();
      final manager = _manager(factory);
      await manager.load();
      final s = await manager.create(
          name: 'Atlas', host: 'h1', username: 'u');

      for (var i = 0; i < 3; i++) {
        await manager.connect(s, secret: 'pw');
        await _flush();
        expect(manager.connectionOf(s.id), TransportState.connected);
        await manager.disconnect(s.id);
        await _flush();
        expect(manager.connectionOf(s.id), TransportState.disconnected);
      }
      expect(factory.seen.length, 3);
      // Same tmux identity every time: the remote session persists.
      expect(
          factory.seen.map((c) => c.tmuxSession).toSet(), {s.tmuxSession});
      manager.dispose();
    });

    test('sessions are independent: one drops, other stays live',
        () async {
      SharedPreferences.setMockInitialValues({});
      final factory = _Factory();
      final manager = _manager(factory);
      await manager.load();
      final a = await manager.create(
          name: 'A', host: 'h1', username: 'u');
      final b = await manager.create(
          name: 'B', host: 'h2', username: 'u');
      await manager.connect(a, secret: 'pw');
      await manager.connect(b, secret: 'pw');
      await _flush();
      expect(manager.connectionOf(a.id), TransportState.connected);
      expect(manager.connectionOf(b.id), TransportState.connected);

      factory.channels.first.dropTransport();
      await _flush();
      await _flush();
      expect(
          manager.connectionOf(a.id), TransportState.disconnected);
      expect(manager.connectionOf(b.id), TransportState.connected);
      expect(manager.sessionStateOf(b.id), SessionState.running);
      manager.dispose();
    });

    test('remove disposes the terminal backend (no leaked streams)',
        () async {
      SharedPreferences.setMockInitialValues({});
      final manager = _manager(_Factory());
      await manager.load();
      final s = await manager.create(
          name: 'Atlas', host: 'h1', username: 'u');
      final backend = manager.open(s.id).backend;
      await manager.remove(s.id);
      // Disposed broadcast streams complete new listeners immediately.
      await expectLater(backend.output, emitsDone);
      await expectLater(backend.onResize, emitsDone);
      manager.dispose();
    });
  });

  group('persistence', () {
    test('id + tmux identity stable across restart, states fresh',
        () async {
      SharedPreferences.setMockInitialValues({});
      final first = _manager(_Factory());
      await first.load();
      final s = await first.create(
          name: 'Atlas editor', host: 'h1', username: 'u');
      await first.connect(s, secret: 'pw');
      await _flush();
      final id = s.id;
      final tmux = s.tmuxSession;
      expect(tmux, isNot(contains('Atlas')));
      first.dispose();

      final second = _manager(_Factory());
      await second.load();
      final restored =
          second.sessions.singleWhere((e) => e.id == id);
      expect(restored.name, 'Atlas editor');
      expect(restored.host, 'h1');
      expect(restored.tmuxSession, tmux);
      // Stale UI state must never claim connected after a restart.
      expect(second.connectionOf(id), TransportState.disconnected);
      expect(second.runtimeOf(id), RuntimeState.unknown);
      expect(second.sessionStateOf(id), SessionState.unknown);
      second.dispose();
    });
  });
}

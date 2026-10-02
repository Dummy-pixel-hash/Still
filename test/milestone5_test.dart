import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:still/src/config/ssh_config.dart';
import 'package:still/src/session/session_manager.dart';
import 'package:still/src/session/still_session.dart';
import 'package:still/src/ssh/ssh_connection.dart';
import 'package:still/src/storage/credential_store.dart';

/// Milestone 5 release-candidate hardening: regression coverage for
/// concrete defects found in the QA audit.
///
/// 1. `disconnect()` is bounded: a hung transport cannot wedge
///    Disconnect/Remove forever.
/// 2. Removing a session disposes its runtime (backend + controller +
///    status subscription); reopening the same id starts clean.

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

/// A factory whose channel teardown hangs: `close()` never returns,
/// simulating a dead socket that never acknowledges the close.
class _HangingCloseFactory implements SshConnectionFactory {
  @override
  Future<SshShellChannel> openShell(SshConfig config) async =>
      _HangingChannel();
}

class _HangingChannel extends _Channel {
  @override
  Future<void> close() => Completer<void>().future;
}

class _Factory implements SshConnectionFactory {
  @override
  Future<SshShellChannel> openShell(SshConfig config) async => _Channel();
}

SessionManager _manager(SshConnectionFactory factory) => SessionManager(
      credentials: MemoryCredentialStore(),
      sshFactory: factory,
    );

Future<StillSession> _session(SessionManager manager) => manager.create(
      name: 'qa',
      host: 'example.com',
      username: 'u',
    );

Future<void> _flush() =>
    Future<void>.delayed(const Duration(milliseconds: 50));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  group('M5 hardening', () {
    test('disconnect returns even when transport close hangs', () async {
      final manager = _manager(_HangingCloseFactory())
        ..disconnectTimeout = const Duration(milliseconds: 100);
      final session = await _session(manager);
      await manager.connect(session, secret: 'pw');
      await _flush();

      // Must complete via the 8s bound, not hang forever.
      await manager
          .disconnect(session.id)
          .timeout(const Duration(seconds: 15));
      expect(manager.connectionOf(session.id),
          TransportState.disconnected);
    });

    test('remove disposes the runtime; reopen starts clean', () async {
      final manager = _manager(_Factory());
      final session = await _session(manager);
      final runtime = manager.open(session.id);
      final firstBackend = runtime.backend;
      final firstController = runtime.controller;

      await manager.remove(session.id);

      // Status subscription is cancelled and both halves disposed.
      expect(runtime.statusSub, isNull);
      expect(firstController.current.name, isNot('connecting'));
      // Reopening the same id materializes a fresh runtime, not the
      // disposed one (writing to a disposed controller must be
      // impossible because the reference is gone).
      final reopened = manager.open(session.id);
      expect(reopened.backend, isNot(same(firstBackend)));
      expect(reopened.controller, isNot(same(firstController)));
    });

    test('disconnect of never-opened session stays disconnected', () async {
      final manager = _manager(_Factory());
      final session = await _session(manager);
      await manager.disconnect(session.id);
      expect(manager.connectionOf(session.id),
          TransportState.disconnected);
    });
  });
}

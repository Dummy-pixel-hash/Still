import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:still/src/session/session_manager.dart';
import 'package:still/src/session/still_session.dart';
import 'package:still/src/ssh/ssh_connection.dart';
import 'package:still/src/storage/credential_store.dart';

import 'package:still/src/config/ssh_config.dart';

class _FakeChannel implements SshShellChannel {
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
  Future<void> close() async {
    await stdoutCtrl.close();
  }
}

class _FakeFactory implements SshConnectionFactory {
  int opens = 0;
  @override
  Future<SshShellChannel> openShell(SshConfig config) async {
    opens++;
    return _FakeChannel();
  }
}

SessionManager _manager(_FakeFactory factory) => SessionManager(
      credentials: MemoryCredentialStore(),
      sshFactory: factory,
    );

void main() {
  test('create assigns internal ids distinct from display names', () async {
    SharedPreferences.setMockInitialValues({});
    final manager = _manager(_FakeFactory());
    await manager.load();
    final a = await manager.create(
        name: 'Atlas', host: 'h1', username: 'u');
    final b = await manager.create(
        name: 'Atlas', host: 'h1', username: 'u');
    expect(a.id, isNot(b.id));
    expect(a.id, isNot(a.name));
    expect(a.tmuxSession, isNotEmpty);
    manager.dispose();
  });

  test('sessions persist across manager restarts (non-secret only)',
      () async {
    SharedPreferences.setMockInitialValues({});
    final first = _manager(_FakeFactory());
    await first.load();
    await first.create(name: 'Atlas', host: 'h1', username: 'u');
    first.dispose();

    final second = _manager(_FakeFactory());
    await second.load();
    expect(second.sessions.length, 1);
    expect(second.sessions.single.name, 'Atlas');
    expect(second.sessions.single.host, 'h1');
    second.dispose();
  });

  test('connect -> running, disconnect -> detached (remote survives)',
      () async {
    SharedPreferences.setMockInitialValues({});
    final factory = _FakeFactory();
    final manager = _manager(factory);
    await manager.load();
    final s = await manager.create(
        name: 'Atlas', host: 'h1', username: 'u');

    expect(manager.sessionStateOf(s.id), SessionState.unknown);
    await manager.connect(s, secret: 'pw');
    expect(factory.opens, 1);
    expect(
        manager.connectionOf(s.id), TransportState.connected);
    expect(manager.sessionStateOf(s.id), SessionState.running);

    await manager.disconnect(s.id);
    // Status travels over a broadcast stream: let it flush.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(
        manager.connectionOf(s.id), TransportState.disconnected);
    // Remote keeps running -> resumable, not destroyed.
    expect(manager.sessionStateOf(s.id), SessionState.detached);
    manager.dispose();
  });

  test('remove drops session and selection', () async {
    SharedPreferences.setMockInitialValues({});
    final manager = _manager(_FakeFactory());
    await manager.load();
    final s = await manager.create(
        name: 'Atlas', host: 'h1', username: 'u');
    manager.select(s.id);
    expect(manager.selected?.id, s.id);
    await manager.remove(s.id);
    expect(manager.sessions, isEmpty);
    expect(manager.selected, isNull);
    manager.dispose();
  });
}

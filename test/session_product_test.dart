import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:still/src/config/ssh_config.dart';
import 'package:still/src/session/session_filter.dart';
import 'package:still/src/session/session_manager.dart';
import 'package:still/src/session/still_session.dart';
import 'package:still/src/settings/app_settings.dart';
import 'package:still/src/ssh/ssh_connection.dart';
import 'package:still/src/storage/credential_store.dart';

class _Channel implements SshShellChannel {
  final stdoutCtrl = StreamController<Uint8List>.broadcast();
  final Completer<void> doneCompleter = Completer<void>();

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

StillSession _named(String name,
        {String project = '', String host = 'h'}) =>
    StillSession(
      id: 'id-$name-$host',
      name: name,
      host: host,
      username: 'u',
      project: project,
      lastActiveAt: DateTime(2026, 1, 1),
    );

void main() {
  group('session edit', () {
    test('rename + reconfigure preserves id and tmux identity', () async {
      SharedPreferences.setMockInitialValues({});
      final manager = _manager(_Factory(), MemoryCredentialStore());
      await manager.load();
      final s = await manager.create(
          name: 'Old', host: 'h1', username: 'u', project: 'Atlas');
      final id = s.id;
      final tmux = s.tmuxSession;

      await manager.update(id,
          name: 'New name', host: 'h2', project: 'Lab', port: 2222);
      final edited =
          manager.sessions.singleWhere((e) => e.id == id);
      expect(edited.name, 'New name');
      expect(edited.host, 'h2');
      expect(edited.project, 'Lab');
      expect(edited.port, 2222);
      // Identity untouched by the rename.
      expect(edited.id, id);
      expect(edited.tmuxSession, tmux);

      // And it survives a restart.
      final again = _manager(_Factory(), MemoryCredentialStore());
      // NOTE: separate prefs would be needed for cross-instance; the
      // mock store is shared, so reload works here.
      await again.load();
      final restored = again.sessions.singleWhere((e) => e.id == id);
      expect(restored.tmuxSession, tmux);
      manager.dispose();
      again.dispose();
    });

    test('update with unknown id throws', () async {
      SharedPreferences.setMockInitialValues({});
      final manager = _manager(_Factory(), MemoryCredentialStore());
      await manager.load();
      await expectLater(
          () => manager.update('nope', name: 'x'), throwsStateError);
      manager.dispose();
    });
  });

  group('saved-key auth selection', () {
    test('connect resolves the session key PEM from secure storage',
        () async {
      SharedPreferences.setMockInitialValues({});
      final creds = MemoryCredentialStore();
      final factory = _Factory();
      final manager = _manager(factory, creds);
      await manager.load();

      final key = await manager.keys
          .add(name: 'laptop', pem: 'PEM-BYTESTEST');
      final s = await manager.create(
        name: 'S',
        host: 'h1',
        username: 'u',
        authKind: SshAuthKind.privateKey,
        keyId: key.id,
      );
      await manager.connect(s);
      await _flush();
      expect(factory.seen.single.privateKeyPem, 'PEM-BYTESTEST');
      manager.dispose();
    });

    test('removed key refuses to dial: explicit error, no broken attempt',
        () async {
      SharedPreferences.setMockInitialValues({});
      final creds = MemoryCredentialStore();
      final factory = _Factory();
      final manager = _manager(factory, creds);
      await manager.load();

      final key =
          await manager.keys.add(name: 'laptop', pem: 'PEM-X');
      final s = await manager.create(
        name: 'S',
        host: 'h1',
        username: 'u',
        authKind: SshAuthKind.privateKey,
        keyId: key.id,
      );
      await manager.keys.remove(key.id);
      // No PEM anywhere: the manager reports a missing-details error
      // instead of handing an empty secret to the transport.
      await expectLater(() => manager.connect(s), throwsStateError);
      await _flush();
      expect(factory.seen, isEmpty);
      expect(manager.errorOf(s.id), isNotNull);
      expect(manager.connectionOf(s.id), TransportState.error);
      manager.dispose();
    });
  });

  group('settings', () {
    test('settings persist and clamp', () async {
      SharedPreferences.setMockInitialValues({});
      final manager = _manager(_Factory(), MemoryCredentialStore());
      await manager.load();
      expect(manager.settings.terminalFontSize, 13);

      await manager.updateSettings(manager.settings.copyWith(
        terminalFontSize: 99,
        cursor: TerminalCursor.bar,
        scrollbackLines: 20000,
        confirmBeforeRemove: false,
      ));
      expect(manager.settings.terminalFontSize,
          AppSettings.maxFontSize);
      expect(manager.settings.cursor, TerminalCursor.bar);
      expect(manager.settings.confirmBeforeRemove, isFalse);

      final again = _manager(_Factory(), MemoryCredentialStore());
      await again.load();
      expect(again.settings.cursor, TerminalCursor.bar);
      expect(again.settings.confirmBeforeRemove, isFalse);
      manager.dispose();
      again.dispose();
    });

    test('scrollback setting sizes newly opened terminals', () async {
      SharedPreferences.setMockInitialValues({});
      final manager = _manager(_Factory(), MemoryCredentialStore());
      await manager.load();
      final s = await manager.create(
          name: 'S', host: 'h1', username: 'u');

      expect(manager.open(s.id).backend.terminal.maxLines, 5000);
      manager.dispose();

      final sized = _manager(_Factory(), MemoryCredentialStore());
      await sized.load();
      await sized.updateSettings(
          sized.settings.copyWith(scrollbackLines: 1000));
      final t = await sized.create(
          name: 'T', host: 'h1', username: 'u');
      expect(sized.open(t.id).backend.terminal.maxLines, 1000);
      sized.dispose();
    });

    test('remembered passwords never land in ordinary prefs', () async {
      SharedPreferences.setMockInitialValues({});
      final factory = _Factory();
      final manager = _manager(factory, MemoryCredentialStore());
      await manager.load();
      final s = await manager.create(
          name: 'S', host: 'h1', username: 'u');
      await manager.connect(s,
          secret: 'super-secret-pw', remember: true);
      await _flush();

      final prefs = await SharedPreferences.getInstance();
      for (final k in prefs.getKeys()) {
        expect(prefs.getString(k) ?? '', isNot(contains('super-secret')));
      }
      manager.dispose();
    });
  });

  group('filter + sort + groups', () {
    final sessions = [
      _named('Editor', project: 'Atlas'),
      _named('Logs', project: 'Atlas'),
      _named('Shell', project: ''),
      _named('Agent', project: 'Lab'),
    ];

    test('search filters name + machine', () {
      expect(filterAndSort(sessions, query: 'edit').length, 1);
      expect(filterAndSort(sessions, query: 'h').length, 4);
      expect(filterAndSort(sessions, query: 'zzz'), isEmpty);
    });

    test('sort name orders case-insensitively', () {
      final names = filterAndSort(sessions, sort: SessionSort.name)
          .map((s) => s.name)
          .toList();
      expect(names, ['Agent', 'Editor', 'Logs', 'Shell']);
    });

    test('groups: named A-Z first, ungrouped last', () {
      final groups = groupByProject(sessions);
      expect(groups.map((g) => g.title), ['Atlas', 'Lab', 'Sessions']);
      expect(groups.first.sessions.length, 2);
      expect(groups.last.sessions.length, 1);
    });

    test('empty input yields one empty group (empty state)', () {
      final groups = groupByProject([]);
      expect(groups.length, 1);
      expect(groups.single.sessions, isEmpty);
    });
  });
}

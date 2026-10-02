import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:still/src/config/ssh_config.dart';
import 'package:still/src/session/session_manager.dart';
import 'package:still/src/session/session_validation.dart';
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

Future<void> _flush() =>
    Future<void>.delayed(const Duration(milliseconds: 50));

SessionManager _manager(_Factory factory, MemoryCredentialStore creds) =>
    SessionManager(credentials: creds, sshFactory: factory);

void main() {
  group('new-session auth staging (state layer)', () {
    test('fresh password session has no usable secret — never auto-dials',
        () async {
      SharedPreferences.setMockInitialValues({});
      final creds = MemoryCredentialStore();
      final factory = _Factory();
      final manager = _manager(factory, creds);
      await manager.load();

      final s = await manager.create(
          name: 'S', host: 'h1', username: 'u');
      expect(await manager.hasUsableSecret(s), isFalse);
      manager.dispose();
    });

    test('staged password becomes resolvable and reaches the transport',
        () async {
      SharedPreferences.setMockInitialValues({});
      final creds = MemoryCredentialStore();
      final factory = _Factory();
      final manager = _manager(factory, creds);
      await manager.load();

      final s = await manager.create(
          name: 'S', host: 'h1', username: 'u');
      await manager.stageSecret(s, 'hunter2');
      expect(await manager.hasUsableSecret(s), isTrue);

      await manager.connect(s);
      await _flush();
      expect(factory.seen.single.password, 'hunter2');
      manager.dispose();
    });

    test('staged one-off key PEM reaches the transport for ask-every-time',
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
        // keyId null = ask every time
      );
      expect(await manager.hasUsableSecret(s), isFalse);

      await manager.stageSecret(s, 'PEM-ONEOFF');
      expect(await manager.hasUsableSecret(s), isTrue);

      await manager.connect(s);
      await _flush();
      expect(factory.seen.single.privateKeyPem, 'PEM-ONEOFF');
      manager.dispose();
    });

    test('empty stage is a no-op — can never seed an empty connect',
        () async {
      SharedPreferences.setMockInitialValues({});
      final creds = MemoryCredentialStore();
      final factory = _Factory();
      final manager = _manager(factory, creds);
      await manager.load();

      final s = await manager.create(
          name: 'S', host: 'h1', username: 'u');
      await manager.stageSecret(s, '');
      expect(await manager.hasUsableSecret(s), isFalse);
      manager.dispose();
    });

    test('remembered staged password goes to secure storage, never prefs',
        () async {
      SharedPreferences.setMockInitialValues({});
      final creds = MemoryCredentialStore();
      final factory = _Factory();
      final manager = _manager(factory, creds);
      await manager.load();

      final s = await manager.create(
          name: 'S', host: 'h1', username: 'u');
      await manager.stageSecret(s, 'staged-secret', remember: true);

      expect(await creds.readPassword(connectionKey('h1', 22, 'u')),
          'staged-secret');

      final prefs = await SharedPreferences.getInstance();
      for (final k in prefs.getKeys()) {
        expect(prefs.getString(k) ?? '',
            isNot(contains('staged-secret')));
      }
      manager.dispose();
    });

    test('staged password without remember stays out of secure storage',
        () async {
      SharedPreferences.setMockInitialValues({});
      final creds = MemoryCredentialStore();
      final factory = _Factory();
      final manager = _manager(factory, creds);
      await manager.load();

      final s = await manager.create(
          name: 'S', host: 'h1', username: 'u');
      await manager.stageSecret(s, 'mem-only');
      expect(await creds.readPassword(connectionKey('h1', 22, 'u')), isNull);
      manager.dispose();
    });

    test('saved key is resolvable without staging; dangling key is not',
        () async {
      SharedPreferences.setMockInitialValues({});
      final creds = MemoryCredentialStore();
      final factory = _Factory();
      final manager = _manager(factory, creds);
      await manager.load();

      final key = await manager.keys.add(name: 'laptop', pem: 'PEM-LAP');
      final withKey = await manager.create(
        name: 'A',
        host: 'h1',
        username: 'u',
        authKind: SshAuthKind.privateKey,
        keyId: key.id,
      );
      expect(await manager.hasUsableSecret(withKey), isTrue);

      final dangling = await manager.create(
        name: 'B',
        host: 'h2',
        username: 'u',
        authKind: SshAuthKind.privateKey,
        keyId: 'gone',
      );
      expect(await manager.hasUsableSecret(dangling), isFalse);
      manager.dispose();
    });
  });

  group('new-session field validation', () {
    test('host required', () {
      expect(validateSessionHost(''), isNotNull);
      expect(validateSessionHost('   '), isNotNull);
      expect(validateSessionHost('dev-fra-02'), isNull);
    });

    test('username required', () {
      expect(validateSessionUsername(''), isNotNull);
      expect(validateSessionUsername('maya'), isNull);
    });

    test('port must be a number in 1-65535, no silent coercion', () {
      expect(validateSessionPort(''), isNotNull);
      expect(validateSessionPort('abc'), isNotNull);
      expect(validateSessionPort('0'), isNotNull);
      expect(validateSessionPort('-1'), isNotNull);
      expect(validateSessionPort('65536'), isNotNull);
      expect(validateSessionPort('22'), isNull);
      expect(validateSessionPort(' 2222 '), isNull);
      // Coercion fallback is gone: invalid port never yields 22.
      expect(tryParseSessionPort('abc'), isNull);
      expect(tryParseSessionPort('65536'), isNull);
      expect(tryParseSessionPort('2222'), 2222);
    });

    test('password required for the form', () {
      expect(validateSessionPassword(''), isNotNull);
      expect(validateSessionPassword('hunter2'), isNull);
    });

    test('pem required when no saved key', () {
      expect(validateSessionPem(''), isNotNull);
      expect(validateSessionPem('   '), isNotNull);
      expect(validateSessionPem('PEM-X'), isNull);
    });
  });
}

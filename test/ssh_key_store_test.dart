import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:still/src/session/ssh_key_store.dart';
import 'package:still/src/storage/credential_store.dart';

SshKeyStore _store(MemoryCredentialStore creds) => SshKeyStore(
      credentials: creds,
    );

void main() {
  test('add/list/remove keys; PEM never lands in prefs', () async {
    SharedPreferences.setMockInitialValues({});
    final creds = MemoryCredentialStore();
    final store = _store(creds);
    await store.load();
    expect(store.keys, isEmpty);

    const pem = '-----BEGIN OPENSSH PRIVATE KEY-----\nabc\n-----END-----';
    final key = await store.add(name: 'laptop', pem: pem);
    expect(key.name, 'laptop');
    expect(store.keys.length, 1);

    // Secret material reachable only via secure storage.
    expect(await store.pemFor(key.id), pem);
    final prefs = await SharedPreferences.getInstance();
    for (final k in prefs.getKeys()) {
      expect(prefs.getString(k) ?? '', isNot(contains('OPENSSH')));
    }

    await store.rename(key.id, 'laptop ed25519');
    expect(store.byId(key.id)?.name, 'laptop ed25519');

    await store.remove(key.id);
    expect(store.keys, isEmpty);
    expect(await store.pemFor(key.id), isNull);
  });

  test('key metadata persists across restarts; empty PEM rejected',
      () async {
    SharedPreferences.setMockInitialValues({});
    final creds = MemoryCredentialStore();
    final first = _store(creds);
    await first.load();
    final key = await first.add(name: 'laptop', pem: 'PEM-BYTES');

    final second = _store(creds);
    await second.load();
    expect(second.keys.length, 1);
    expect(second.byId(key.id)?.name, 'laptop');
    expect(await second.pemFor(key.id), 'PEM-BYTES');

    await expectLater(
      second.add(name: 'empty', pem: '  '),
      throwsArgumentError,
    );
  });
}

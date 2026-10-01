import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Secure credential storage behind an interface.
///
/// * Production path: [SecureCredentialStore] (Keychain / Keystore /
///   DPAPI via flutter_secure_storage) — the only place secrets live.
/// * Tests / spike fallback: [MemoryCredentialStore].
/// Non-secret connection params (host/user/session) go to shared_preferences
/// via `PrefsStore`, never here.
abstract class CredentialStore {
  Future<void> savePassword(String key, String password);
  Future<String?> readPassword(String key);
  Future<void> deletePassword(String key);

  Future<void> savePrivateKey(String key, String pem);
  Future<String?> readPrivateKey(String key);
  Future<void> deletePrivateKey(String key);
}

String connectionKey(String host, int port, String username) =>
    'still/ssh/$username@$host:$port';

class SecureCredentialStore implements CredentialStore {
  SecureCredentialStore([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<void> savePassword(String key, String password) =>
      _storage.write(key: '$key/password', value: password);

  @override
  Future<String?> readPassword(String key) =>
      _storage.read(key: '$key/password');

  @override
  Future<void> deletePassword(String key) =>
      _storage.delete(key: '$key/password');

  @override
  Future<void> savePrivateKey(String key, String pem) =>
      _storage.write(key: '$key/key', value: pem);

  @override
  Future<String?> readPrivateKey(String key) =>
      _storage.read(key: '$key/key');

  @override
  Future<void> deletePrivateKey(String key) =>
      _storage.delete(key: '$key/key');
}

class MemoryCredentialStore implements CredentialStore {
  final _map = <String, String>{};

  @override
  Future<void> savePassword(String key, String password) async {
    _map['$key/password'] = password;
  }

  @override
  Future<String?> readPassword(String key) async => _map['$key/password'];

  @override
  Future<void> deletePassword(String key) async {
    _map.remove('$key/password');
  }

  @override
  Future<void> savePrivateKey(String key, String pem) async {
    _map['$key/key'] = pem;
  }

  @override
  Future<String?> readPrivateKey(String key) async => _map['$key/key'];

  @override
  Future<void> deletePrivateKey(String key) async {
    _map.remove('$key/key');
  }
}

import 'package:flutter/foundation.dart';

import '../storage/credential_store.dart';
import '../storage/prefs_store.dart';

/// A saved SSH identity: human-readable name in prefs, secret material
/// only in secure storage. The PEM (and optional passphrase) are never
/// exposed except to the SSH transport at connect time.
class SshKey {
  SshKey({
    required this.id,
    required this.name,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  final String id;
  String name;
  final DateTime createdAt;

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'createdAt': createdAt.toIso8601String(),
      };

  factory SshKey.fromJson(Map<String, Object?> json) => SshKey(
        id: (json['id'] as String?) ??
            'key-${DateTime.now().microsecondsSinceEpoch}',
        name: (json['name'] as String?) ?? 'Key',
        createdAt: DateTime.tryParse(
            (json['createdAt'] as String?) ?? ''),
      );
}

String _pemSlot(String id) => 'still/keys/$id/pem';
String _passphraseSlot(String id) => 'still/keys/$id/passphrase';

/// Local key management on the existing secure-storage architecture.
/// No cloud sync; sessions reference keys by stable [SshKey.id].
class SshKeyStore extends ChangeNotifier {
  SshKeyStore({PrefsStore? prefs, CredentialStore? credentials})
      : _prefs = prefs ?? PrefsStore(),
        _credentials = credentials ?? SecureCredentialStore();

  final PrefsStore _prefs;
  final CredentialStore _credentials;
  final List<SshKey> _keys = [];
  int _counter = 0;

  List<SshKey> get keys => List.unmodifiable(_keys);

  SshKey? byId(String? id) {
    if (id == null) return null;
    try {
      return _keys.firstWhere((k) => k.id == id);
    } catch (_) {
      return null;
    }
  }

  Future<void> load() async {
    final raw = await _prefs.loadKeys();
    _keys
      ..clear()
      ..addAll(raw.map(SshKey.fromJson));
    notifyListeners();
  }

  Future<void> _persist() async {
    await _prefs.saveKeys(_keys.map((k) => k.toJson()).toList());
  }

  /// Import a key. Only the name is persisted in prefs; the PEM and
  /// optional passphrase go straight to secure storage.
  Future<SshKey> add({
    required String name,
    required String pem,
    String? passphrase,
  }) async {
    final trimmed = pem.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('Private key material is empty.');
    }
    final key = SshKey(
      id: 'key-${DateTime.now().microsecondsSinceEpoch}-${_counter++}',
      name: name.trim().isEmpty ? 'Unnamed key' : name.trim(),
    );
    try {
      await _credentials.savePrivateKey(_pemSlot(key.id), trimmed);
      if (passphrase != null && passphrase.isNotEmpty) {
        await _credentials.savePassword(
            _passphraseSlot(key.id), passphrase);
      }
    } catch (_) {
      await _deleteSecretBestEffort(key.id);
      rethrow;
    }
    _keys.add(key);
    await _persist();
    notifyListeners();
    return key;
  }

  Future<String?> pemFor(String id) async {
    try {
      return _credentials.readPrivateKey(_pemSlot(id));
    } catch (_) {
      return null;
    }
  }

  Future<String?> passphraseFor(String id) async {
    try {
      return _credentials.readPassword(_passphraseSlot(id));
    } catch (_) {
      return null;
    }
  }

  Future<void> rename(String id, String name) async {
    final key = byId(id);
    if (key == null) return;
    key.name = name.trim().isEmpty ? key.name : name.trim();
    await _persist();
    notifyListeners();
  }

  Future<void> remove(String id) async {
    _keys.removeWhere((k) => k.id == id);
    await _deleteSecretBestEffort(id);
    await _persist();
    notifyListeners();
  }

  Future<void> _deleteSecretBestEffort(String id) async {
    try {
      await _credentials.deletePrivateKey(_pemSlot(id));
    } catch (_) {}
    try {
      await _credentials.deletePassword(_passphraseSlot(id));
    } catch (_) {}
  }
}

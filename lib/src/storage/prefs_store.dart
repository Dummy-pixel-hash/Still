import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Non-secret persistence only. Secrets live in [CredentialStore].
class PrefsStore {
  static const _kHost = 'still.last.host';
  static const _kPort = 'still.last.port';
  static const _kUser = 'still.last.user';
  static const _kSession = 'still.last.tmux';
  static const _kSessions = 'still.sessions.v1';
  static const _kKeys = 'still.keys.v1';
  static const _kSettings = 'still.settings.v1';

  Future<void> saveLastConnection({
    required String host,
    required int port,
    required String username,
    required String tmuxSession,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kHost, host);
    await prefs.setInt(_kPort, port);
    await prefs.setString(_kUser, username);
    await prefs.setString(_kSession, tmuxSession);
  }

  Future<LastConnection?> loadLastConnection() async {
    final prefs = await SharedPreferences.getInstance();
    final host = prefs.getString(_kHost);
    final user = prefs.getString(_kUser);
    if (host == null || user == null) return null;
    return LastConnection(
      host: host,
      port: prefs.getInt(_kPort) ?? 22,
      username: user,
      tmuxSession: prefs.getString(_kSession) ?? 'still',
    );
  }

  /// Workspace session list (non-secret fields only). Secrets stay in
  /// CredentialStore keyed by connectionKey().
  Future<void> saveSessions(List<Map<String, Object?>> sessions) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kSessions, jsonEncode(sessions));
  }

  Future<List<Map<String, Object?>>> loadSessions() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kSessions);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw) as List;
      return decoded.whereType<Map>().map((m) {
        return m.map((k, v) => MapEntry(k.toString(), v));
      }).toList();
    } catch (_) {
      return [];
    }
  }

  /// Saved SSH key metadata (names only — PEMs live in CredentialStore).
  Future<void> saveKeys(List<Map<String, Object?>> keys) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kKeys, jsonEncode(keys));
  }

  Future<List<Map<String, Object?>>> loadKeys() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kKeys);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw) as List;
      return decoded.whereType<Map>().map((m) {
        return m.map((k, v) => MapEntry(k.toString(), v));
      }).toList();
    } catch (_) {
      return [];
    }
  }

  /// Local app settings (no secrets).
  Future<void> saveSettings(Map<String, Object?> settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kSettings, jsonEncode(settings));
  }

  Future<Map<String, Object?>?> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kSettings);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw) as Map;
      return decoded.map((k, v) => MapEntry(k.toString(), v));
    } catch (_) {
      return null;
    }
  }
}

class LastConnection {
  const LastConnection({
    required this.host,
    required this.port,
    required this.username,
    required this.tmuxSession,
  });

  final String host;
  final int port;
  final String username;
  final String tmuxSession;
}

import 'package:shared_preferences/shared_preferences.dart';

/// Non-secret persistence only. Secrets live in [CredentialStore].
class PrefsStore {
  static const _kHost = 'still.last.host';
  static const _kPort = 'still.last.port';
  static const _kUser = 'still.last.user';
  static const _kSession = 'still.last.tmux';

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

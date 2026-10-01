/// Connection parameters for the Milestone-1 spike.
///
/// Secrets (password / key PEM) are held in memory only. Callers are
/// responsible for loading them from [CredentialStore] before connecting
/// and never persisting them to shared_preferences / logs.
enum SshAuthKind { password, privateKey }

class SshConfig {
  const SshConfig({
    required this.host,
    this.port = 22,
    required this.username,
    this.authKind = SshAuthKind.password,
    this.password,
    this.privateKeyPem,
    this.privateKeyPassphrase,
    this.tmuxSession = 'still',
    this.termType = 'xterm-256color',
    this.cols = 80,
    this.rows = 24,
    this.acceptAnyHostKey = true,
  });

  final String host;
  final int port;
  final String username;
  final SshAuthKind authKind;
  final String? password;
  final String? privateKeyPem;
  final String? privateKeyPassphrase;
  final String tmuxSession;
  final String termType;
  final int cols;
  final int rows;

  /// Spike default: accept any host key (with on-screen warning).
  /// Production must switch to known_hosts persistence (see README).
  final bool acceptAnyHostKey;

  bool get isValid =>
      host.trim().isNotEmpty &&
      username.trim().isNotEmpty &&
      port > 0 &&
      port < 65536 &&
      (authKind == SshAuthKind.privateKey
          ? (privateKeyPem?.trim().isNotEmpty ?? false)
          : true);

  SshConfig copyWith({
    String? host,
    int? port,
    String? username,
    SshAuthKind? authKind,
    String? password,
    String? privateKeyPem,
    String? privateKeyPassphrase,
    String? tmuxSession,
    String? termType,
    int? cols,
    int? rows,
    bool? acceptAnyHostKey,
  }) {
    return SshConfig(
      host: host ?? this.host,
      port: port ?? this.port,
      username: username ?? this.username,
      authKind: authKind ?? this.authKind,
      password: password ?? this.password,
      privateKeyPem: privateKeyPem ?? this.privateKeyPem,
      privateKeyPassphrase: privateKeyPassphrase ?? this.privateKeyPassphrase,
      tmuxSession: tmuxSession ?? this.tmuxSession,
      termType: termType ?? this.termType,
      cols: cols ?? this.cols,
      rows: rows ?? this.rows,
      acceptAnyHostKey: acceptAnyHostKey ?? this.acceptAnyHostKey,
    );
  }
}

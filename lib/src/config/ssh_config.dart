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
    this.workdir = '',
    this.startCommand = '',
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

  /// Working directory for a newly created remote session. Empty or `~`
  /// means the login default (home). Threaded into the tmux attach
  /// command; never interpreted locally.
  final String workdir;

  /// Command the new remote session runs at creation (fixed allowlisted
  /// value from [startCommandFor], never user input). Empty means the
  /// default shell. Applies at creation only — reattach never re-runs it.
  final String startCommand;

  final String tmuxSession;
  final String termType;
  final int cols;
  final int rows;

  /// Accepts any host key (disclosed on-screen in the New Session form
  /// and the terminal overlay). Production must switch to known_hosts
  /// persistence (see README). No verification is performed — nothing
  /// here should ever claim otherwise.
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
    String? workdir,
    String? startCommand,
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
      workdir: workdir ?? this.workdir,
      startCommand: startCommand ?? this.startCommand,
      tmuxSession: tmuxSession ?? this.tmuxSession,
      termType: termType ?? this.termType,
      cols: cols ?? this.cols,
      rows: rows ?? this.rows,
      acceptAnyHostKey: acceptAnyHostKey ?? this.acceptAnyHostKey,
    );
  }
}

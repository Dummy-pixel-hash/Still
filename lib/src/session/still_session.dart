import '../config/ssh_config.dart';

/// Card preview flavor. Purely visual (which static preview the card
/// shows); says nothing about transport. Not a tmux concept.
enum SessionKind { shell, agent, editor, git, monitor, logs }

/// Command a new remote session runs at creation for each [SessionKind].
/// Null means the default shell. These are fixed allowlisted strings —
/// never user input — passed as tmux new-session's creation command, so
/// they apply only when the persistent session is created; reattaching
/// never re-runs them.
String? startCommandFor(SessionKind kind) => switch (kind) {
      SessionKind.shell => null,
      SessionKind.agent => 'claude',
      SessionKind.editor => 'nvim',
      SessionKind.git => 'lazygit',
      SessionKind.monitor => 'btop',
      SessionKind.logs => 'tail -f',
    };

/// Remote session existence. `detached` = previously connected, remote
/// keeps running (tmux), resumable. `unknown` = never connected here.
enum SessionState { running, detached, unknown }

/// Transport state. Kept separate from [SessionState] on purpose.
/// (Named to avoid clashing with Flutter's own TransportState.)
enum TransportState { disconnected, connecting, connected, error }

/// Remote runtime readiness. Kept separate from both states above.
enum RuntimeState { unknown, creating, ready, unavailable, error }

/// A workspace session. `id` is the internal identity (never the display
/// name). Secrets are never stored here — see CredentialStore.
class StillSession {
  StillSession({
    required this.id,
    required this.name,
    required this.host,
    this.port = 22,
    required this.username,
    this.authKind = SshAuthKind.password,
    String? tmuxSession,
    this.kind = SessionKind.shell,
    this.workdir = '~',
    this.project = '',
    this.keyId,
    DateTime? createdAt,
    DateTime? lastActiveAt,
  })  : tmuxSession = tmuxSession ?? _slugFor(id),
        createdAt = createdAt ?? DateTime.now(),
        lastActiveAt = lastActiveAt ?? DateTime.now();

  final String id;
  String name;
  String host;
  int port;
  String username;
  SshAuthKind authKind;

  /// Internal persistent-runtime handle. Never shown in product UI
  /// (tmux stays invisible infrastructure). Final: edits and renames
  /// must never change it.
  final String tmuxSession;

  SessionKind kind;
  String workdir;

  /// Lightweight grouping label (e.g. "Atlas"). Free text, may be empty.
  String project;

  /// Saved-key reference (stable id, never the key name). Null means
  /// "ask at connect time". Secrets stay in secure storage.
  String? keyId;
  final DateTime createdAt;
  DateTime lastActiveAt;

  static String _slugFor(String id) {
    final slug = id
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    final trimmed = slug.isEmpty ? 'still' : slug;
    return trimmed.length > 32 ? trimmed.substring(0, 32) : trimmed;
  }

  /// `user@host` label for cards.
  String get machine => '$username@$host';

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'host': host,
        'port': port,
        'username': username,
        'authKind': authKind.name,
        'tmuxSession': tmuxSession,
        'kind': kind.name,
        'workdir': workdir,
        'project': project,
        'keyId': keyId,
        'createdAt': createdAt.toIso8601String(),
        'lastActiveAt': lastActiveAt.toIso8601String(),
      };

  factory StillSession.fromJson(Map<String, Object?> json) {
    String str(String key, String fallback) =>
        (json[key] as String?) ?? fallback;
    return StillSession(
      id: str('id', 'session-${DateTime.now().microsecondsSinceEpoch}'),
      name: str('name', 'Session'),
      host: str('host', ''),
      port: (json['port'] as num?)?.toInt() ?? 22,
      username: str('username', ''),
      authKind: (json['authKind'] as String?) == 'privateKey'
          ? SshAuthKind.privateKey
          : SshAuthKind.password,
      tmuxSession: json['tmuxSession'] as String?,
      kind: SessionKind.values.asNameMap()[json['kind']] ??
          SessionKind.shell,
      workdir: str('workdir', '~'),
      project: str('project', ''),
      keyId: json['keyId'] as String?,
      createdAt: DateTime.tryParse(str('createdAt', '')),
      lastActiveAt: DateTime.tryParse(str('lastActiveAt', '')),
    );
  }

  StillSession copy() => StillSession.fromJson(toJson());
}

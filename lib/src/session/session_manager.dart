import 'dart:async';

import 'package:flutter/foundation.dart';

import '../config/ssh_config.dart';
import '../settings/app_settings.dart';
import '../ssh/dartssh2_connection.dart';
import '../ssh/ssh_connection.dart';
import '../storage/credential_store.dart';
import '../storage/prefs_store.dart';
import '../terminal/xterm_backend.dart';
import 'connection_errors.dart';
import 'remote_session_controller.dart';
import 'ssh_key_store.dart';
import 'still_session.dart';

/// Per-session live wiring. Created lazily on first open, kept while the
/// app lives so a terminal keeps its scrollback when navigating away.
class OpenRuntime {
  OpenRuntime(this.backend, this.controller);

  final XtermBackend backend;
  final RemoteSessionController controller;
  StreamSubscription<RemoteSessionStatus>? statusSub;
}

/// State layer: UI -> SessionManager -> (existing) SSH/tmux/terminal.
///
/// Sessions (identity + metadata) live here. Connection state and runtime
/// state are tracked separately per session id. Transport stays behind the
/// existing [SshConnectionFactory] / [RemoteSessionController] seams —
/// nothing here imports dartssh2 or xterm directly except for constructing
/// the stock implementations.
class SessionManager extends ChangeNotifier {
  SessionManager({
    PrefsStore? prefs,
    CredentialStore? credentials,
    SshConnectionFactory? sshFactory,
    SshKeyStore? keys,
  })  : _prefs = prefs ?? PrefsStore(),
        _credentials = credentials ?? SecureCredentialStore(),
        _sshFactory = sshFactory ?? DartSsh2ConnectionFactory(),
        keys = keys ??
            SshKeyStore(
              prefs: prefs ?? PrefsStore(),
              credentials: credentials ?? SecureCredentialStore(),
            );

  final PrefsStore _prefs;
  final CredentialStore _credentials;
  final SshConnectionFactory _sshFactory;

  /// Saved SSH identities (names here, secrets in secure storage).
  final SshKeyStore keys;

  AppSettings _settings = const AppSettings();
  AppSettings get settings => _settings;

  final List<StillSession> _sessions = [];
  final Map<String, TransportState> _connections = {};
  final Map<String, RuntimeState> _runtimes = {};
  final Map<String, String?> _errors = {};
  final Map<String, OpenRuntime> _open = {};
  final Map<String, String> _memorySecrets = {};

  String? _selectedId;
  bool _loaded = false;
  int _idCounter = 0;

  List<StillSession> get sessions => List.unmodifiable(_sessions);
  String? get selectedId => _selectedId;
  bool get loaded => _loaded;

  StillSession? get selected {
    final id = _selectedId;
    if (id == null) return null;
    try {
      return _sessions.firstWhere((s) => s.id == id);
    } catch (_) {
      return null;
    }
  }

  TransportState connectionOf(String id) =>
      _connections[id] ?? TransportState.disconnected;

  RuntimeState runtimeOf(String id) => _runtimes[id] ?? RuntimeState.unknown;

  String? errorOf(String id) => _errors[id];

  /// Derived remote-session state for cards: connected -> running,
  /// ever-connected -> detached (resumable), else unknown.
  SessionState sessionStateOf(String id) {
    if (_connections[id] == TransportState.connected) {
      return SessionState.running;
    }
    if (_everConnected.contains(id)) return SessionState.detached;
    return SessionState.unknown;
  }

  final Set<String> _everConnected = {};

  int get runningCount => _sessions
      .where((s) => sessionStateOf(s.id) == SessionState.running)
      .length;

  Future<void> load() async {
    final raw = await _prefs.loadSessions();
    _sessions
      ..clear()
      ..addAll(raw.map(StillSession.fromJson));
    await keys.load();
    final stored = await _prefs.loadSettings();
    if (stored != null) {
      try {
        _settings = AppSettings.fromJson(stored);
      } catch (_) {
        // Corrupt settings: keep defaults.
      }
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> updateSettings(AppSettings next) async {
    _settings = next;
    await _prefs.saveSettings(next.toJson());
    notifyListeners();
  }

  Future<void> _persist() async {
    await _prefs.saveSessions(_sessions.map((s) => s.toJson()).toList());
  }

  /// Create a session (metadata only — no connection yet).
  Future<StillSession> create({
    required String name,
    required String host,
    required String username,
    int port = 22,
    SshAuthKind authKind = SshAuthKind.password,
    SessionKind kind = SessionKind.shell,
    String workdir = '~',
    String project = '',
    String? keyId,
  }) async {
    final session = StillSession(
      id: 's-${DateTime.now().microsecondsSinceEpoch}-${_idCounter++}',
      name: name.trim().isEmpty ? 'Session' : name.trim(),
      host: host.trim(),
      port: port,
      username: username.trim(),
      authKind: authKind,
      kind: kind,
      workdir: workdir.trim().isEmpty ? '~' : workdir.trim(),
      project: project.trim(),
      keyId: keyId,
    );
    _sessions.add(session);
    await _persist();
    notifyListeners();
    return session;
  }

  /// Edit a session. Only metadata changes — `id` and `tmuxSession` are
  /// final on the model, so renames and reconfiguration can never change
  /// the underlying runtime identity.
  Future<void> update(
    String id, {
    String? name,
    String? host,
    int? port,
    String? username,
    SshAuthKind? authKind,
    SessionKind? kind,
    String? workdir,
    String? project,
    String? Function()? keyId,
  }) async {
    final s = _sessions.firstWhere((e) => e.id == id);
    if (name != null) {
      s.name = name.trim().isEmpty ? s.name : name.trim();
    }
    if (host != null && host.trim().isNotEmpty) s.host = host.trim();
    if (port != null && port > 0 && port < 65536) s.port = port;
    if (username != null && username.trim().isNotEmpty) {
      s.username = username.trim();
    }
    if (authKind != null) s.authKind = authKind;
    if (kind != null) s.kind = kind;
    if (workdir != null) {
      s.workdir = workdir.trim().isEmpty ? '~' : workdir.trim();
    }
    if (project != null) s.project = project.trim();
    if (keyId != null) s.keyId = keyId();
    s.lastActiveAt = DateTime.now();
    await _persist();
    notifyListeners();
  }

  Future<void> remove(String id) async {
    await disconnect(id);
    final runtime = _open.remove(id);
    await runtime?.statusSub?.cancel();
    runtime?.controller.dispose();
    runtime?.backend.dispose();
    _sessions.removeWhere((s) => s.id == id);
    _connections.remove(id);
    _runtimes.remove(id);
    _errors.remove(id);
    _memorySecrets.remove(id);
    if (_selectedId == id) _selectedId = null;
    await _persist();
    notifyListeners();
  }

  void select(String? id) {
    _selectedId = id;
    if (id != null) {
      try {
        final s = _sessions.firstWhere((s) => s.id == id);
        s.lastActiveAt = DateTime.now();
        unawaited(_persist());
      } catch (_) {
        // Selection of unknown id: ignore.
      }
    }
    notifyListeners();
  }

  /// Lazily materialize the terminal + controller for a session.
  OpenRuntime open(String id) {
    final existing = _open[id];
    if (existing != null) return existing;
    final backend =
        XtermBackend(maxLines: _settings.scrollbackLines);
    final controller = RemoteSessionController(
      terminal: backend,
      sshFactory: _sshFactory,
    );
    final runtime = OpenRuntime(backend, controller);
    runtime.statusSub = controller.status.listen((status) {
      _onRemoteStatus(id, status, controller.lastError);
    });
    _open[id] = runtime;
    return runtime;
  }

  void _onRemoteStatus(
      String id, RemoteSessionStatus status, String? error) {
    switch (status) {
      case RemoteSessionStatus.connecting:
        _connections[id] = TransportState.connecting;
        _runtimes[id] = RuntimeState.creating;
      case RemoteSessionStatus.live:
        _connections[id] = TransportState.connected;
        _runtimes[id] = RuntimeState.ready;
        _errors[id] = null;
        _everConnected.add(id);
      case RemoteSessionStatus.closed:
        // Transport gone (clean close or drop). The remote runtime keeps
        // running under tmux; we only ever report ourselves disconnected.
        // Never claim connected/running without a live channel.
        _connections[id] = TransportState.disconnected;
        _runtimes[id] = RuntimeState.unknown;
      case RemoteSessionStatus.error:
        _connections[id] = TransportState.error;
        _runtimes[id] = RuntimeState.error;
        _errors[id] = friendlyConnectionError(error ?? '');
      case RemoteSessionStatus.idle:
        _connections[id] = TransportState.disconnected;
    }
    notifyListeners();
  }

  SshConfig _configFor(StillSession s, {String? secret}) {
    final secretValue = secret ??
        _memorySecrets[s.id] ??
        ''; // resolved from CredentialStore by caller when needed
    // Seed the pty + tmux attach with the LIVE view size, not 80x24.
    // TerminalView.autoResize corrects the size right after layout, but
    // the first tmux frame is drawn at attach size — stale defaults here
    // mean a visibly wrong first frame and a tmux redraw on every open.
    final runtime = _open[s.id];
    return SshConfig(
      host: s.host,
      port: s.port,
      username: s.username,
      authKind: s.authKind,
      password: s.authKind == SshAuthKind.password ? secretValue : null,
      privateKeyPem:
          s.authKind == SshAuthKind.privateKey ? secretValue : null,
      tmuxSession: s.tmuxSession,
      cols: runtime?.backend.cols ?? 80,
      rows: runtime?.backend.rows ?? 24,
      acceptAnyHostKey: true, // spike behavior, unchanged this milestone
    );
  }

  /// Connect (or re-attach) a session's persistent runtime. `secret` is the
  /// password or key PEM, kept in memory; persisted only if [remember] set.
  /// When the session names a saved key and no explicit secret is given,
  /// the key's PEM is resolved from secure storage (never from prefs).
  Future<void> connect(StillSession s,
      {String? secret, bool remember = false}) async {
    final runtime = open(s.id);
    String? resolved = secret ?? _memorySecrets[s.id];
    resolved ??= await _keyPemFor(s);
    resolved ??= await _readStoredSecret(s);
    if (resolved != null && resolved.isNotEmpty) {
      _memorySecrets[s.id] = resolved;
    }
    _errors[s.id] = null;
    try {
      await runtime.controller.connect(_configFor(s));
      s.lastActiveAt = DateTime.now();
      if (remember && (resolved ?? '').isNotEmpty) {
        await _storeSecret(s, resolved!);
      }
      await _persist();
    } catch (e) {
      _errors[s.id] = friendlyConnectionError(e);
      _connections[s.id] = TransportState.error;
      _runtimes[s.id] = RuntimeState.error;
      notifyListeners();
      rethrow;
    }
  }

  /// Disconnect transport only — the remote runtime keeps running (tmux).
  Future<void> disconnect(String id) async {
    final runtime = _open[id];
    if (runtime == null) {
      _connections[id] = TransportState.disconnected;
      notifyListeners();
      return;
    }
    await runtime.controller.disconnect();
  }

  /// Re-attach to the same persistent runtime over a fresh channel.
  Future<void> reconnect(String id) async {
    final runtime = _open[id];
    final session = _sessions.firstWhere((s) => s.id == id);
    if (runtime == null) {
      await connect(session);
      return;
    }
    try {
      // Prefer stored/memory secret path so reconnect works after restart.
      final secret = _memorySecrets[id] ??
          await _keyPemFor(session) ??
          await _readStoredSecret(session);
      if (secret != null && secret.isNotEmpty) {
        _memorySecrets[id] = secret;
        await runtime.controller.connect(_configFor(session));
      } else {
        await runtime.controller.reconnect();
      }
      session.lastActiveAt = DateTime.now();
      await _persist();
    } catch (e) {
      _errors[id] = friendlyConnectionError(e);
      _connections[id] = TransportState.error;
      notifyListeners();
      rethrow;
    }
  }

  /// Saved-key PEM for key-auth sessions that name a key. Returns null
  /// when the session uses another auth path or the key is gone (then the
  /// terminal screen falls back to asking, as before).
  Future<String?> _keyPemFor(StillSession s) async {
    if (s.authKind != SshAuthKind.privateKey) return null;
    final keyId = s.keyId;
    if (keyId == null || keyId.isEmpty) return null;
    final pem = await keys.pemFor(keyId);
    return (pem == null || pem.isEmpty) ? null : pem;
  }

  Future<String?> _readStoredSecret(StillSession s) async {
    final key = connectionKey(s.host, s.port, s.username);
    try {
      if (s.authKind == SshAuthKind.privateKey) {
        return _credentials.readPrivateKey(key);
      }
      return _credentials.readPassword(key);
    } catch (_) {
      return null;
    }
  }

  Future<void> _storeSecret(StillSession s, String secret) async {
    final key = connectionKey(s.host, s.port, s.username);
    try {
      if (s.authKind == SshAuthKind.privateKey) {
        await _credentials.savePrivateKey(key, secret);
      } else {
        await _credentials.savePassword(key, secret);
      }
    } catch (_) {
      // Secure storage may be unavailable on some dev hosts; the
      // in-memory secret still works for this run.
    }
  }

  @override
  void dispose() {
    for (final runtime in _open.values) {
      runtime.statusSub?.cancel();
      runtime.controller.dispose();
      runtime.backend.dispose();
    }
    _open.clear();
    super.dispose();
  }
}

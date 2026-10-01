import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../config/ssh_config.dart';
import '../ssh/ssh_connection.dart';
import '../terminal/terminal_backend.dart';
import '../tmux/tmux.dart';

enum RemoteSessionStatus { idle, connecting, live, closed, error }

/// Orchestrates: SSH shell <-> tmux attach <-> [TerminalBackend].
///
/// UI-agnostic and backend-agnostic: it never imports dartssh2 or xterm.
/// Reconnect simply re-opens the shell and re-attaches to the same tmux
/// session, which is the persistence story.
class RemoteSessionController {
  RemoteSessionController({
    required TerminalBackend terminal,
    required SshConnectionFactory sshFactory,
  })  : _terminal = terminal,
        _sshFactory = sshFactory;

  final TerminalBackend _terminal;
  final SshConnectionFactory _sshFactory;

  SshShellChannel? _channel;
  StreamSubscription<String>? _termOutSub;
  StreamSubscription<Uint8List>? _remoteSub;
  StreamSubscription<TerminalSize>? _resizeSub;

  SshConfig? _lastConfig;
  TmuxPlan? _tmux;

  final _status = StreamController<RemoteSessionStatus>.broadcast();
  RemoteSessionStatus _current = RemoteSessionStatus.idle;

  Stream<RemoteSessionStatus> get status => _status.stream;
  RemoteSessionStatus get current => _current;
  TerminalBackend get terminal => _terminal;
  String? get lastError => _lastError;
  String? _lastError;

  void _emit(RemoteSessionStatus s) {
    _current = s;
    if (!_status.isClosed) _status.add(s);
  }

  /// Connect: open SSH shell, bridge streams, attach to tmux.
  Future<void> connect(SshConfig config) async {
    await disconnect();
    _emit(RemoteSessionStatus.connecting);
    _lastError = null;
    _lastConfig = config;
    _tmux = TmuxPlan(sessionName: config.tmuxSession);
    try {
      final channel = await _sshFactory.openShell(config);
      _channel = channel;

      // Remote -> terminal (bytes are UTF-8 VT stream).
      _remoteSub = channel.stdout.listen(
        (bytes) => _terminal.feed(utf8.decode(bytes, allowMalformed: true)),
        onError: (Object e) {
          _lastError = '$e';
          _emit(RemoteSessionStatus.error);
        },
        onDone: () => _emit(RemoteSessionStatus.closed),
      );

      // User keystrokes / mouse reports -> remote.
      _termOutSub = _terminal.output.listen(
        (data) => channel.write(Uint8List.fromList(utf8.encode(data))),
      );

      // View resize -> SSH window-change. tmux follows the pty size for
      // attached clients; see docs/terminal-matrix.md for the manual
      // `tmux refresh-client` fallback.
      _resizeSub = _terminal.onResize.listen((size) {
        try {
          channel.resize(size.cols, size.rows);
        } catch (_) {
          // Resize must never crash the session.
        }
      });

      unawaited(channel.done.then((_) {
        if (_current == RemoteSessionStatus.live ||
            _current == RemoteSessionStatus.connecting) {
          _emit(RemoteSessionStatus.closed);
        }
      }));

      // Enter (or create) the persistent tmux session.
      channel.write(Uint8List.fromList(utf8.encode(
        _tmux!.attachCommand(cols: config.cols, rows: config.rows),
      )));

      _emit(RemoteSessionStatus.live);
    } catch (e) {
      _lastError = '$e';
      _emit(RemoteSessionStatus.error);
      rethrow;
    }
  }

  /// Re-attach to the same tmux session over a fresh SSH channel.
  Future<void> reconnect() async {
    final config = _lastConfig;
    if (config == null) {
      throw StateError('No previous connection to reconnect to.');
    }
    await connect(config.copyWith(
      cols: _terminal.cols,
      rows: _terminal.rows,
    ));
  }

  Future<void> disconnect() async {
    await _termOutSub?.cancel();
    await _remoteSub?.cancel();
    await _resizeSub?.cancel();
    _termOutSub = null;
    _remoteSub = null;
    _resizeSub = null;
    try {
      await _channel?.close();
    } catch (_) {
      // Best effort.
    }
    _channel = null;
    if (_current == RemoteSessionStatus.live ||
        _current == RemoteSessionStatus.connecting ||
        _current == RemoteSessionStatus.error) {
      _emit(RemoteSessionStatus.closed);
    }
  }

  void dispose() {
    unawaited(disconnect());
    _status.close();
  }
}

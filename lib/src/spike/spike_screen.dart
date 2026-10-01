import 'dart:async';

import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

import '../config/ssh_config.dart';
import '../session/remote_session_controller.dart';
import '../ssh/dartssh2_connection.dart';
import '../storage/credential_store.dart';
import '../storage/prefs_store.dart';
import '../terminal/xterm_backend.dart';

/// Milestone-1 spike screen — deliberately NOT the workspace UI.
///
/// One connection form + one interactive terminal. Proves end-to-end:
/// SSH -> tmux attach -> interactive pty. The polished workspace UI
/// (sessions list, tabs, settings) comes later and talks to
/// [RemoteSessionController], never to SSH/xterm directly.
class SpikeScreen extends StatefulWidget {
  const SpikeScreen({super.key});

  @override
  State<SpikeScreen> createState() => _SpikeScreenState();
}

class _SpikeScreenState extends State<SpikeScreen> {
  final _host = TextEditingController();
  final _port = TextEditingController(text: '22');
  final _user = TextEditingController();
  final _password = TextEditingController();
  final _key = TextEditingController();
  final _tmux = TextEditingController(text: 'still');

  SshAuthKind _authKind = SshAuthKind.password;
  bool _remember = false;

  late final XtermBackend _backend;
  late final RemoteSessionController _session;
  late final CredentialStore _credentials;
  late final PrefsStore _prefs;

  StreamSubscription<RemoteSessionStatus>? _statusSub;
  RemoteSessionStatus _status = RemoteSessionStatus.idle;
  String _log = '';

  @override
  void initState() {
    super.initState();
    _backend = XtermBackend();
    _session = RemoteSessionController(
      terminal: _backend,
      sshFactory: DartSsh2ConnectionFactory(),
    );
    _credentials = SecureCredentialStore();
    _prefs = PrefsStore();
    _statusSub = _session.status.listen((s) {
      setState(() => _status = s);
    });
    _restoreLast();
  }

  Future<void> _restoreLast() async {
    try {
      final last = await _prefs.loadLastConnection();
      if (last == null || !mounted) return;
      setState(() {
        _host.text = last.host;
        _port.text = '${last.port}';
        _user.text = last.username;
        _tmux.text = last.tmuxSession;
      });
    } catch (_) {
      // Prefs are best-effort in the spike.
    }
  }

  @override
  void dispose() {
    _statusSub?.cancel();
    _session.dispose();
    _backend.dispose();
    _host.dispose();
    _port.dispose();
    _user.dispose();
    _password.dispose();
    _key.dispose();
    _tmux.dispose();
    super.dispose();
  }

  SshConfig _buildConfig() {
    return SshConfig(
      host: _host.text.trim(),
      port: int.tryParse(_port.text.trim()) ?? 22,
      username: _user.text.trim(),
      authKind: _authKind,
      password:
          _authKind == SshAuthKind.password ? _password.text : null,
      privateKeyPem:
          _authKind == SshAuthKind.privateKey ? _key.text : null,
      tmuxSession: sanitizeTmux(_tmux.text),
    );
  }

  static String sanitizeTmux(String raw) =>
      raw.trim().isEmpty ? 'still' : raw.trim();

  Future<void> _connect() async {
    final config = _buildConfig();
    if (!config.isValid) {
      setState(() => _log = 'Fill host + username first.');
      return;
    }
    setState(() => _log = 'Connecting to ${config.username}@${config.host}…');
    try {
      await _session.connect(config.copyWith(
        cols: _backend.cols,
        rows: _backend.rows,
      ));
      await _prefs.saveLastConnection(
        host: config.host,
        port: config.port,
        username: config.username,
        tmuxSession: config.tmuxSession,
      );
      if (_remember) {
        final key = connectionKey(config.host, config.port, config.username);
        try {
          if (config.authKind == SshAuthKind.password &&
              (config.password ?? '').isNotEmpty) {
            await _credentials.savePassword(key, config.password!);
          }
          if (config.authKind == SshAuthKind.privateKey &&
              (config.privateKeyPem ?? '').isNotEmpty) {
            await _credentials.savePrivateKey(key, config.privateKeyPem!);
          }
        } catch (e) {
          // Secure storage may be unavailable on some dev machines.
          if (mounted) setState(() => _log = 'Connected (remember failed: $e)');
          return;
        }
      }
      if (mounted) {
        setState(() => _log =
            'Live — attached to tmux "${config.tmuxSession}".');
      }
    } catch (e) {
      if (mounted) setState(() => _log = 'Connect failed: $e');
    }
  }

  Future<void> _reconnect() async {
    setState(() => _log = 'Reconnecting (re-attach tmux)…');
    try {
      await _session.reconnect();
      if (mounted) setState(() => _log = 'Re-attached.');
    } catch (e) {
      if (mounted) setState(() => _log = 'Reconnect failed: $e');
    }
  }

  Future<void> _disconnect() async {
    await _session.disconnect();
    if (mounted) setState(() => _log = 'Disconnected. tmux keeps running.');
  }

  @override
  Widget build(BuildContext context) {
    final live = _status == RemoteSessionStatus.live;
    final busy = _status == RemoteSessionStatus.connecting;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Still — terminal/runtime spike (M1)'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Chip(label: Text(_status.name)),
          ),
        ],
      ),
      body: Column(
        children: [
          _connectionBar(live: live, busy: busy),
          if (_log.isNotEmpty)
            Container(
              width: double.infinity,
              color: Colors.amber.shade100,
              padding: const EdgeInsets.all(8),
              child: Text(_log, style: const TextStyle(fontSize: 12)),
            ),
          const Divider(height: 1),
          Expanded(
            child: Container(
              color: Colors.black,
              child: TerminalView(
                _backend.terminal,
                autofocus: true,
                padding: const EdgeInsets.all(8),
              ),
            ),
          ),
          _hintBar(),
        ],
      ),
    );
  }

  Widget _connectionBar({required bool live, required bool busy}) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.all(8),
      child: Row(
        children: [
          SizedBox(width: 160, child: _field(_host, 'host')),
          const SizedBox(width: 8),
          SizedBox(width: 70, child: _field(_port, 'port',
              inputType: TextInputType.number)),
          const SizedBox(width: 8),
          SizedBox(width: 120, child: _field(_user, 'user')),
          const SizedBox(width: 8),
          DropdownButton<SshAuthKind>(
            value: _authKind,
            items: const [
              DropdownMenuItem(
                  value: SshAuthKind.password, child: Text('password')),
              DropdownMenuItem(
                  value: SshAuthKind.privateKey, child: Text('key')),
            ],
            onChanged: (v) => setState(() => _authKind = v!),
          ),
          const SizedBox(width: 8),
          if (_authKind == SshAuthKind.password)
            SizedBox(
                width: 140, child: _field(_password, 'password', obscure: true))
          else
            SizedBox(width: 200, child: _field(_key, 'PEM key', mono: true)),
          const SizedBox(width: 8),
          SizedBox(width: 110, child: _field(_tmux, 'tmux')),
          const SizedBox(width: 8),
          ElevatedButton(
              onPressed: (live || busy) ? null : _connect,
              child: const Text('Connect')),
          const SizedBox(width: 8),
          OutlinedButton(
              onPressed: live ? _reconnect : null,
              child: const Text('Reconnect')),
          const SizedBox(width: 8),
          OutlinedButton(
              onPressed: live ? _disconnect : null,
              child: const Text('Disconnect')),
          const SizedBox(width: 8),
          Row(children: [
            Checkbox(
                value: _remember,
                onChanged: (v) => setState(() => _remember = v ?? false)),
            const Text('remember secret', style: TextStyle(fontSize: 12)),
          ]),
        ],
      ),
    );
  }

  Widget _field(TextEditingController c, String hint,
      {bool obscure = false,
      bool mono = false,
      TextInputType? inputType}) {
    return TextField(
      controller: c,
      obscureText: obscure,
      keyboardType: inputType,
      decoration: InputDecoration(
          labelText: hint, border: const OutlineInputBorder(), isDense: true),
      style: mono
          ? const TextStyle(fontFamily: 'monospace', fontSize: 12)
          : null,
    );
  }

  Widget _hintBar() {
    return Container(
      padding: const EdgeInsets.all(8),
      alignment: Alignment.centerLeft,
      child: const Text(
        'Spike checks: type, resize window, scroll, run vim/htop, unicode/truecolor printf, '
        'copy-select, kill network → Reconnect, `tmux ls` attach. See docs/terminal-matrix.md. '
        'Host key currently accept-any (spike only).',
        style: TextStyle(fontSize: 11, color: Colors.black54),
      ),
    );
  }
}

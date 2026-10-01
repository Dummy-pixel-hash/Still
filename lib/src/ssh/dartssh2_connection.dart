import 'dart:async';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

import '../config/ssh_config.dart';
import 'ssh_connection.dart';

/// Pure-Dart SSH transport (works on Windows + Android, no native deps).
class DartSsh2ConnectionFactory implements SshConnectionFactory {
  @override
  Future<SshShellChannel> openShell(SshConfig config) async {
    final socket = await SSHSocket.connect(config.host, config.port);
    final List<SSHKeyPair>? identities = await _loadIdentities(config);

    final client = SSHClient(
      socket,
      username: config.username,
      identities: identities,
      onPasswordRequest: config.authKind == SshAuthKind.password
          ? () => config.password ?? ''
          : null,
      onVerifyHostKey: (type, fingerprint) async =>
          config.acceptAnyHostKey,
      keepAliveInterval: const Duration(seconds: 15),
    );

    final session = await client.shell(
      pty: SSHPtyConfig(
        type: config.termType,
        width: config.cols,
        height: config.rows,
      ),
    );
    return _DartSsh2Shell(session, client);
  }

  Future<List<SSHKeyPair>?> _loadIdentities(SshConfig config) async {
    if (config.authKind != SshAuthKind.privateKey) return null;
    final pem = config.privateKeyPem?.trim() ?? '';
    if (pem.isEmpty) return null;
    // Supports OpenSSH + PKCS5/8 PEM; passphrase optional.
    final pairs = SSHKeyPair.fromPem(
      pem,
      config.privateKeyPassphrase,
    );
    return pairs;
  }
}

class _DartSsh2Shell implements SshShellChannel {
  _DartSsh2Shell(this._session, this._client);

  final SSHSession _session;
  final SSHClient _client;

  @override
  Stream<Uint8List> get stdout => _session.stdout;

  @override
  void write(Uint8List data) => _session.write(data);

  @override
  void resize(int cols, int rows,
      [int pixelWidth = 0, int pixelHeight = 0]) {
    _session.resizeTerminal(cols, rows, pixelWidth, pixelHeight);
  }

  @override
  Future<void> get done => _session.done;

  @override
  Future<void> close() async {
    _session.close();
    _client.close();
  }
}

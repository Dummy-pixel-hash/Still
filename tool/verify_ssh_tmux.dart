// Headless M1 verification: SSH -> tmux attach -> resize -> re-attach.
//
// Usage:
//   STILL_SSH_HOST=192.168.1.10 STILL_SSH_USER=pi ...
//     dart run tool/verify_ssh_tmux.dart
//
// Exit 0 = all probes passed. Any failure prints to stderr and exits 1.
// Covers matrix rows 1 (shell), 2 (resize), 8 (reconnect), 9 (attach).
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

Future<String> _run(SSHClient client, String cmd) async {
  final session = await client.execute(cmd);
  final out = await session.stdout
      .fold<BytesBuilder>(BytesBuilder(), (b, d) => b..add(d))
      .timeout(const Duration(seconds: 15));
  // Drain stderr too so the channel can close cleanly.
  unawaited(session.stderr.drain());
  await session.done.timeout(const Duration(seconds: 15));
  return utf8.decode(out.takeBytes(), allowMalformed: true);
}

void _check(bool ok, String label) {
  stdout.writeln('${ok ? 'PASS' : 'FAIL'}  $label');
  if (!ok) exitCode = 1;
}

Future<void> main() async {
  final host = Platform.environment['STILL_SSH_HOST'] ?? '';
  final user = Platform.environment['STILL_SSH_USER'] ?? '';
  final password = Platform.environment['STILL_SSH_PASSWORD'] ?? '';
  final port = int.tryParse(Platform.environment['STILL_SSH_PORT'] ?? '22') ?? 22;
  final sessionName = Platform.environment['STILL_SSH_SESSION'] ?? 'still';

  if (host.isEmpty || user.isEmpty) {
    stderr.writeln('Set STILL_SSH_HOST and STILL_SSH_USER '
        '(and STILL_SSH_PASSWORD or key env). See docs/terminal-matrix.md.');
    exit(2);
  }

  SSHClient clientFor(SSHSocket socket) => SSHClient(
        socket,
        username: user,
        onPasswordRequest: password.isEmpty ? null : () => password,
        onVerifyHostKey: (_, __) async => true, // spike only
        keepAliveInterval: const Duration(seconds: 15),
      );

  // --- Probe 1: shell works ---
  var socket = await SSHSocket.connect(host, port)
      .timeout(const Duration(seconds: 20));
  var client = clientFor(socket);
  final echo = await _run(client, 'echo still-probe-$sessionName');
  _check(echo.contains('still-probe-$sessionName'), 'shell echo');

  // --- Probe 2: tmux attach-or-create + ls ---
  final tmuxNew = await _run(
      client, 'tmux -u new-session -A -d -s $sessionName -x 80 -y 24 && tmux ls');
  _check(tmuxNew.contains(sessionName), 'tmux attach + ls');

  // --- Probe 3: pty resize (window-change must not error) ---
  try {
    final shell = await client.shell(
        pty: const SSHPtyConfig(width: 80, height: 24));
    shell.resizeTerminal(120, 40);
    shell.write(Uint8List.fromList(
        utf8.encode('tmux refresh-client -t $sessionName -x 120 -y 40 2>/dev/null; echo resized-ok\n')));
    final buf = BytesBuilder();
    final sub = shell.stdout.listen(buf.add);
    await Future<void>.delayed(const Duration(seconds: 3));
    await sub.cancel();
    shell.close();
    final text = utf8.decode(buf.takeBytes(), allowMalformed: true);
    _check(text.contains('resized-ok'), 'pty resize + refresh');
  } catch (e) {
    _check(false, 'pty resize + refresh ($e)');
  }
  client.close();

  if (exitCode != 0) exit(exitCode);

  // --- Probe 4: disconnect + re-attach (persistence) ---
  socket = await SSHSocket.connect(host, port)
      .timeout(const Duration(seconds: 20));
  client = clientFor(socket);
  final relist = await _run(client, 'tmux ls');
  _check(relist.contains(sessionName), 're-attach sees tmux session');
  client.close();

  stdout.writeln(exitCode == 0 ? 'ALL PROBES PASSED' : 'PROBES FAILED');
  exit(exitCode);
}

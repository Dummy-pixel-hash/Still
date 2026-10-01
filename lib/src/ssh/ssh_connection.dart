import 'dart:typed_data';

import '../config/ssh_config.dart';

/// A single interactive remote shell (pty channel).
///
/// Hides dartssh2 (or any future transport) behind a narrow interface so
/// the session layer never imports `package:dartssh2` directly.
abstract class SshShellChannel {
  Stream<Uint8List> get stdout;
  void write(Uint8List data);
  void resize(int cols, int rows, [int pixelWidth = 0, int pixelHeight = 0]);
  Future<void> get done;
  Future<void> close();
}

abstract class SshConnectionFactory {
  Future<SshShellChannel> openShell(SshConfig config);
}

/// Clean abstraction over the terminal emulator.
///
/// Milestone 1 ships [XtermBackend] (package:xterm). A future
/// Ghostty/libghostty-vt backend implements this same interface via
/// Dart FFI — see `ghostty_vt_adapter.dart`. The session layer
/// ([RemoteSessionController]) only talks to this interface, so the
/// emulator can be swapped without touching SSH/tmux/storage code.
///
/// Contract:
/// * [feed] pushes decoded remote bytes (UTF-8) into the emulator.
/// * [output] emits user keystrokes / mouse reports to send to the remote.
/// * [onResize] fires when the *view* size changes (TerminalView autoResize
///   or explicit call). The session layer forwards this to SSH + tmux.
/// * Implementations must support: scrollback, alt-screen buffer,
///   mouse modes, truecolor/SGR, Unicode/wide chars, bracketed paste.
abstract class TerminalBackend {
  /// Push remote output into the emulator.
  void feed(String data);

  /// Bytes the user typed / mouse reports to send to the remote pty.
  Stream<String> get output;

  /// Fired when the emulator view size changes (cols x rows).
  Stream<TerminalSize> get onResize;

  int get cols;
  int get rows;

  void resize(int cols, int rows);

  void dispose();
}

class TerminalSize {
  const TerminalSize(this.cols, this.rows);
  final int cols;
  final int rows;

  @override
  String toString() => '${cols}x$rows';
}

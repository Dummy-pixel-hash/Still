import 'dart:async';

import 'package:xterm/xterm.dart';

import 'terminal_backend.dart';

/// Current [TerminalBackend] implementation backed by `package:xterm`.
///
/// xterm.dart gives us: VT parsing, scrollback, alt-screen, mouse modes,
/// SGR truecolor, wide-char support, selection/copy, and TerminalView with
/// autoResize — enough to verify the full Milestone-1 matrix. It is the
/// stand-in until the Ghostty/libghostty-vt FFI backend lands; the public
/// surface it exposes to the session layer is exactly [TerminalBackend].
class XtermBackend implements TerminalBackend {
  XtermBackend({int maxLines = 5000, int cols = 80, int rows = 24})
      : terminal = Terminal(maxLines: maxLines) {
    terminal.onOutput = (data) => _output.add(data);
    terminal.onResize = (w, h, _, __) {
      _cols = w;
      _rows = h;
      _resize.add(TerminalSize(w, h));
    };
    // Seed initial size; TerminalView.autoResize will correct it on layout.
    terminal.resize(cols, rows);
    _cols = cols;
    _rows = rows;
  }

  /// The underlying emulator. Passed directly to `TerminalView`.
  final Terminal terminal;

  final _output = StreamController<String>.broadcast();
  final _resize = StreamController<TerminalSize>.broadcast();

  late int _cols;
  late int _rows;

  @override
  void feed(String data) => terminal.write(data);

  @override
  Stream<String> get output => _output.stream;

  @override
  Stream<TerminalSize> get onResize => _resize.stream;

  @override
  int get cols => _cols;

  @override
  int get rows => _rows;

  @override
  void resize(int cols, int rows) => terminal.resize(cols, rows);

  @override
  void dispose() {
    _output.close();
    _resize.close();
  }
}

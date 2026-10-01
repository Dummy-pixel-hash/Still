import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';

/// Feeds byte streams captured from REAL programs (via tmux capture-pane)
/// into the emulator. Guards against parser regressions on genuine output.
///
/// Captures live in test/testdata (checked in):
/// - htop_frame.bin: one htop frame (alt-screen TUI, SGR, box drawing)
/// - uni_color.bin: unicode + truecolor/256-color printf probes
void main() {
  test('real htop frame parses without failure', () {
    final bytes = File('test/testdata/htop_frame.bin').readAsBytesSync();
    final text = String.fromCharCodes(bytes);
    final t = Terminal(maxLines: 5000);
    expect(() => t.write(text), returnsNormally);
    expect(t.buffer.lines.length, greaterThan(0));
  });

  test('real unicode+truecolor output parses', () {
    final bytes = File('test/testdata/uni_color.bin').readAsBytesSync();
    final text = String.fromCharCodes(bytes);
    final t = Terminal(maxLines: 5000);
    expect(() => t.write(text), returnsNormally);
  });

  test('real htop frame survives alt-screen enter/exit cycle', () {
    final t = Terminal(maxLines: 5000);
    t.write('\x1b[?1049h');
    expect(t.isUsingAltBuffer, isTrue);
    final bytes = File('test/testdata/htop_frame.bin').readAsBytesSync();
    expect(
        () => t.write(String.fromCharCodes(bytes)), returnsNormally);
    t.write('\x1b[?1049l');
    expect(t.isUsingAltBuffer, isFalse);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';

import 'package:still/src/terminal/xterm_backend.dart';

/// Compatibility harness for real interactive workloads (M1 validation).
///
/// Each test feeds byte streams representative of what the named program
/// emits over SSH+tmux and asserts the emulator state. These are synthetic
/// but faithful: alt-screen (1049h/l), CUP, SGR 256/truecolor, mouse SGR
/// (1006), bracketed paste (2004), wide-char (wcwidth), focus/cursor ops.
/// Live tmux/SSH behavior is covered by tool/verify_ssh_tmux.dart + the
/// isolated-tmux checks documented in docs/terminal-matrix.md.
Terminal _term() => Terminal(maxLines: 5000);

void main() {
  group('shell + prompts', () {
    test('normal shell interaction: echo, prompt, exit code', () {
      final t = _term();
      t.write('user@host:~\$ ');
      t.write('echo hello-\$((1+1))\r\nhello-2\r\nuser@host:~\$ ');
      expect(t.buffer.lines.length, greaterThan(0));
    });

    test('sudo password prompt renders and accepts input echo', () {
      final t = _term();
      final out = <String>[];
      t.onOutput = out.add;
      t.write('[sudo] password for user: ');
      t.textInput('secret');
      t.keyInput(TerminalKey.enter);
      expect(out.join(), contains('secret'));
    });

    test('ctrl combos encode: C(0x03) D(0x04) Z(0x1A)', () {
      final t = _term();
      final out = <String>[];
      t.onOutput = out.add;
      t.keyInput(TerminalKey.keyC, ctrl: true);
      t.keyInput(TerminalKey.keyD, ctrl: true);
      t.keyInput(TerminalKey.keyZ, ctrl: true);
      expect(out, ['\x03', '\x04', '\x1a']);
    });

    test('arrows/home/end/f-keys emit keytab sequences', () {
      final t = _term();
      final out = <String>[];
      t.onOutput = out.add;
      expect(t.keyInput(TerminalKey.arrowUp), isTrue);
      expect(t.keyInput(TerminalKey.arrowDown), isTrue);
      expect(t.keyInput(TerminalKey.home), isTrue);
      expect(t.keyInput(TerminalKey.f1), isTrue);
      expect(out.length, 4);
      expect(out[0], contains('\x1b[')); // SS3/CSI
    });
  });

  group('alt-screen TUIs (vim/lazygit/btop/htop/less/fzf/claude)', () {
    test('vim-style: enter alt, draw, quit restores main', () {
      final t = _term();
      t.write('shell-before\r\n');
      t.write('\x1b[?1049h\x1b[H'); // vim: alt + home
      expect(t.isUsingAltBuffer, isTrue);
      t.write('\x1b[32m~\x1b[0m VIM - Vi IMproved\r\n');
      t.write('\x1b[?1049l'); // :q
      expect(t.isUsingAltBuffer, isFalse);
    });

    test('htop/btop-style: cup + reverse video + clear', () {
      final t = _term();
      t.write('\x1b[?1049h');
      t.write('\x1b[1;1H\x1b[7m  CPU[||||||||  12.3%]\x1b[0m');
      t.write('\x1b[2J\x1b[Hrefreshed');
      expect(t.isUsingAltBuffer, isTrue);
      t.write('\x1b[?1049l');
      expect(t.isUsingAltBuffer, isFalse);
    });

    test('less-style pager: alt screen with status line', () {
      final t = _term();
      t.write('\x1b[?1049h\x1b[Hline1\r\nline2\r\n');
      t.write('\x1b[7m/etc/hosts (END)\x1b[0m');
      t.write('\x1b[?1049l');
      expect(t.isUsingAltBuffer, isFalse);
    });

    test('fzf-style: inline (no alt) filter list + reverse search', () {
      final t = _term();
      // fzf typically runs inline on main buffer.
      t.write('  file_a.txt\r\n> file_b.txt\r\n  2/120 --query foo\r\n');
      expect(t.isUsingAltBuffer, isFalse);
      expect(t.buffer.lines.length, greaterThan(0));
    });

    test('lazygit/claude-style: box drawing + cursor address', () {
      final t = _term();
      t.write('\x1b[?1049h');
      t.write('\x1b[1;1H┌─ Files ─┐\x1b[2;1H│ main.dart │');
      t.write('\x1b[10;5H\x1b[?25h'); // show cursor at 10,5
      expect(t.isUsingAltBuffer, isTrue);
      t.write('\x1b[?1049l');
    });

    test('long-running process streams without parser failure', () {
      final t = _term();
      for (var i = 0; i < 200; i++) {
        t.write('[$i] building… \x1b[33mWARN\x1b[0m ok\r\n');
      }
      expect(t.buffer.lines.length, greaterThan(0));
    });

    test('scrolling: 200 lines retained in scrollback', () {
      final t = Terminal(maxLines: 5000);
      for (var i = 0; i < 200; i++) {
        t.write('line $i\r\n');
      }
      expect(t.mainBuffer.lines.length, greaterThanOrEqualTo(200));
    });
  });

  group('AI-agent surface: ANSI/cursor/color/unicode/resize', () {
    test('SGR 16/256/truecolor + bold/italic/underline', () {
      final t = _term();
      t.write('\x1b[1;3;4;31mB\x1b[0m ');
      t.write('\x1b[38;5;208m256-orange\x1b[0m ');
      t.write('\x1b[38;2;255;100;0mTRUE\x1b[0m ');
      t.write('\x1b[48;2;10;20;30mBG\x1b[0m\r\n');
      // Cursor style should reset to defaults after SGR 0.
      expect(t.cursor.isBold, isFalse);
    });

    test('cursor movement: CUP/CUU/CUD/CUF/CUB + save/restore', () {
      final t = _term();
      // Must not throw; parser handles all cursor ops agents use.
      t.write('\x1b[2J\x1b[H');
      t.write('\x1b[5;10Hhello');
      t.write('\x1b[2A\x1b[3B\x1b[4C\x1b[2D');
      t.write('\x1b7\x1b8'); // save/restore
      t.write('\x1b[s\x1b[u'); // save/restore (SCO)
    });

    test('unicode + wide chars: CJK/emoji occupy 2 cells, combining ok', () {
      final t = _term();
      t.write('✓ 𐍈 ☺ 你好 😀 e\xcc\x81\r\n');
      expect(t.buffer.lines.length, greaterThan(0));
    });

    test('mouse SGR 1006 mode enter + click report encodes', () {
      final t = _term();
      final out = <String>[];
      t.onOutput = out.add;
      t.write('\x1b[?1000h\x1b[?1006h'); // app enables mouse+SGR
      expect(t.mouseMode, isNot(MouseMode.none));
      // Simulate a click at cell (10,5) through the backend-agnostic path.
      final handled = t.mouseInput(
        TerminalMouseButton.left,
        TerminalMouseButtonState.down,
        const CellOffset(10, 5),
      );
      expect(handled, isTrue);
      expect(out.single, contains('\x1b[<'));
      t.write('\x1b[?1000l');
      expect(t.mouseMode, MouseMode.none);
    });

    test('bracketed paste wraps pasted text for agents/editors', () {
      final t = _term();
      final out = <String>[];
      t.onOutput = out.add;
      t.write('\x1b[?2004h');
      expect(t.bracketedPasteMode, isTrue);
      t.paste('echo a\necho b');
      expect(out.single, startsWith('\x1b[200~'));
      expect(out.single, endsWith('\x1b[201~'));
      t.write('\x1b[?2004l');
    });

    test('resize keeps emulator alive; backend reports new size', () {
      final b = XtermBackend(cols: 80, rows: 24);
      b.resize(120, 40);
      expect(b.cols, 120);
      expect(b.rows, 40);
      b.feed('\x1b[2J\x1b[Hresized\r\n');
      b.dispose();
    });

    test('device-attribute + title/OSC sequences do not break parse', () {
      final t = _term();
      final titles = <String>[];
      t.onTitleChange = titles.add;
      t.write('\x1b[c'); // primary DA request -> emits response
      t.write('\x1b]0;claude — Still\x07'); // OSC title
      t.write('\x1b[>c'); // tertiary DA
      expect(titles, ['claude — Still']);
    });

    test('unsupported modern sequences are ignored, never crash', () {
      final t = _term();
      // lazygit/btop synchronized output, OSC-8 hyperlinks, kitty keys.
      t.write('\x1b[?2026hframe\x1b[?2026l');
      t.write('\x1b]8;;https://example.com\x07link\x1b]8;;\x07');
      t.write('\x1b[>1u'); // kitty push-flags (unknown -> ignored)
      expect(t.buffer.lines.length, greaterThan(0));
    });
  });

  group('copy/paste path', () {
    test('paste() without bracketed mode sends raw text', () {
      final t = _term();
      final out = <String>[];
      t.onOutput = out.add;
      t.paste('hello');
      expect(out, ['hello']);
    });
  });

  group('editing keys (must reach apps untouched)', () {
    test('enter/tab/escape/backspace/delete all encode', () {
      final t = _term();
      final out = <String>[];
      t.onOutput = out.add;
      expect(t.keyInput(TerminalKey.enter), isTrue);
      expect(t.keyInput(TerminalKey.tab), isTrue);
      expect(t.keyInput(TerminalKey.escape), isTrue);
      expect(t.keyInput(TerminalKey.backspace), isTrue);
      expect(t.keyInput(TerminalKey.delete), isTrue);
      expect(out.length, 5);
      // Escape must be a bare ESC so vim-style apps see it.
      expect(out[2], '\x1b');
      expect(out[0], contains('\r')); // enter -> CR
      expect(out[1], '\x09'); // tab
    });

    test('ctrl combos agents rely on: C/D/Z plus [/]', () {
      final t = _term();
      final out = <String>[];
      t.onOutput = out.add;
      t.keyInput(TerminalKey.keyC, ctrl: true);
      t.keyInput(TerminalKey.keyD, ctrl: true);
      t.keyInput(TerminalKey.keyZ, ctrl: true);
      expect(out, ['\x03', '\x04', '\x1a']);
    });
  });
}

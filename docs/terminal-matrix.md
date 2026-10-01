# Still M1 — terminal/runtime verification matrix

Scope: **one real SSH connection → remote tmux → interactive terminal**.
No workspace UI. Each row: what to do in the spike screen, what success looks like.

Prereqs on the remote: OpenSSH server + `tmux` installed (`tmux -V`).
Spike screen: `flutter run` → fill host/user/auth + tmux name → **Connect**.

| # | Check | Steps in spike | Pass criteria |
|---|-------|----------------|---------------|
| 1 | Basic shell interaction | Type `echo hello-$((1+1))`, `ls`, `sleep 1 &` + Enter | Output renders, prompt returns, exit codes correct |
| 2 | Resize | Resize the app window / rotate Android; run `stty size` before + after | `stty size` matches new geometry; tmux panes reflow, no wrapping garbage |
| 3 | Scrolling | `seq 1 200`, then scroll up with mouse/touch, `Shift+PgUp` on desktop | Scrollback to line 1, live tail follows new output |
| 4 | Mouse input | `vim` → `:set mouse=a` → click/drag; `tmux set -g mouse on` → click panes, scroll | Clicks move cursor / select panes; wheel scrolls alt-screen instead of history |
| 5 | Alternate-screen TUIs | Run `vim file`, `htop` (or `top`), `less /etc/hosts` then `q` | Full-screen app renders, quits cleanly back to shell with history intact |
| 6 | Unicode / truecolor | `printf '\u2713 \U00010348 \u263a\n'`; `printf '\e[38;2;255;100;0mTRUE\e[0m \e[1;34mBOLD-BLUE\e[0m\n'`; `curl -s https://…` Nerd-font glyphs optional | Glyphs (not tofu), orange TRUE + bold blue, no parser crash |
| 7 | Copy / paste | Select text in terminal → copy (Ctrl+Shift+C / long-press) → paste into shell; paste multiline `echo a\necho b` | Clipboard round-trips; bracketed paste keeps multiline intact |
| 8 | Disconnect / reconnect | **Disconnect** (or kill network/VPN), run `sleep 30` before drop, then **Reconnect** | `tmux ls` still shows session; `jobs` / sleep output survived; prompt usable |
| 9 | Attach to existing tmux | In another client: `tmux new -s still` + `echo from-other`; in spike connect with same name | Spike shows `from-other`; both clients mirror; `tmux ls` lists one session |
| 10 | Auth paths | Password login; then key login (paste OpenSSH PEM, optional passphrase) | Both connect; wrong password surfaces error in status bar, no crash |

## Manual tmux probes (run inside the spike terminal)

```sh
tmux ls                 # session `still` present
tmux display -p '#S #{session_windows}w #{session_attached} attached'
echo $TERM              # xterm-256color
stty size               # matches view, changes on resize
printf '\e[38;2;1;2;3m...\e[0m\n'   # truecolor
```

## Headless harness

```sh
STILL_SSH_HOST=… STILL_SSH_USER=… STILL_SSH_PASSWORD=… \
  dart run tool/verify_ssh_tmux.dart
```

Runs: connect → `echo` probe → `tmux new -A` → resize probe →
disconnect → re-attach → `tmux ls` contains session. Exit 0 = matrix rows
1/2/8/9 covered without the UI.

## Known spike limitations (by design)

- Host key: accept-any with no known_hosts (production: persist + TOFU prompt).
- `remember secret` uses flutter_secure_storage; on Linux dev it may fall back
  with a warning — Windows Credential Manager / Android Keystore are the real targets.
- Emulator is xterm.dart; Ghostty/libghostty-vt FFI is a documented drop-in
  (`lib/src/terminal/ghostty_vt_adapter.dart`) — same `TerminalBackend` surface.

---

# Validation results — 2026-10-01 (terminal/runtime compatibility)

Goal was to decide: **(A)** xterm.dart is good enough for the MVP, or
**(B)** move to Ghostty/libghostty-vt now. Method per row: `harness`
(`flutter test test/terminal_compat_test.dart` + `test/real_capture_test.dart`),
`live` (isolated local tmux server `tmux -L stilltest`, tmux 3.5a), or
`review` (source-level verification where on-device/manual run is required).
`still-frontend` was not touched. No UI changes. No new dependencies.

## Results by area

| # | Area | Verdict | Evidence |
|---|------|---------|----------|
| 1 | Normal shell interaction | PASS | harness (echo/prompt) + live (`echo MARKER123` round-trip via send-keys/capture-pane) |
| 2 | Interactive programs (htop, less) | PASS | live: `htop` ran, 3.4 KB frame with CPU/Mem/PID labels, quit with `q` back to bash; `less /etc/hosts` rendered file content, quit cleanly. Real htop frame checked into `test/testdata/htop_frame.bin` and fed to the emulator in `real_capture_test.dart` — parses, no crash |
| 3 | Claude Code / AI-agent workflows | PASS (with caveats) | `claude --version` → 2.1.239 present. Interactive session NOT started (would need API quota + TTY). Agent-critical surface verified in harness: alt-screen, CUP/cursor ops, DA/CPR (`CSI 6n` → cursor-position report, needed by Ink), SGR 16/256/truecolor, Unicode/wide, bracketed paste, resize, long streams. OSC title (`\x1b]0;…\x07`) updates correctly |
| 4 | Neovim | LIKELY PASS (not run live) | `nvim`/`vim` not installed here and no sudo to install. vim-style VT cycle (1049h → draw → 1049l, main buffer intact) passes in harness; vim's sequence set ⊆ verified parser ops. Recommend one live `nvim` pass on a dev machine before workspace milestone |
| 5 | lazygit | LIKELY PASS (not run live) | Binary not installed. Box-drawing + cursor-address + 256-color harness passes. lazygit also uses synchronized-output (2026) — verified IGNORED without crash (no tearing protection, cosmetic only) |
| 6 | btop/htop | PASS (htop live) | htop live as above. `btop` not installed; same VT family as htop (alt-screen + SGR + truecolor), covered |
| 7 | fzf | LIKELY PASS (not run live) | Not installed. fzf runs inline (main buffer, no alt-screen) with reverse-video selection — pattern covered in harness |
| 8 | less / pagers | PASS | live `less` as above |
| 9 | sudo/password prompts | PASS (harness) | Prompt renders, typed input + Enter encode correctly. Live `sudo` not exercised (no sudo rights in this env) |
| 10 | Ctrl+C / Ctrl+D / Ctrl+Z | PASS | harness: C→`0x03`, D→`0x04`, Z→`0x1A`. live: `sleep 30` + `C-c` → `^C`, prompt returned |
| 11 | Alternate screen | PASS | harness enter/draw/exit cycles for vim/htop/less/lazygit styles; `isUsingAltBuffer` toggles correctly; scrollback preserved on exit |
| 12 | Mouse interaction | PASS (protocol) | harness: app enables `1000h+1006h` → `mouseMode != none`, click at cell encodes SGR `\x1b[<…`, disable restores `none`. Real click-through needs a manual UI pass (spike screen) |
| 13 | Unicode / wide chars | PASS | harness (✓ 𐍈 ☺ CJK 😀 combining `é`, wcwidth-backed) + live printf probe rendered in pane + `real_capture_test.dart` on genuine bytes |
| 14 | Truecolor / ANSI | PASS | harness (16/256/RGB fg+bg, bold/italic/underline, reset) + live printf (`TRUE` orange, `BOLD-BLUE`, `256-ORANGE`) rendered + real-bytes test |
| 15 | Terminal resize | PASS | harness (`XtermBackend.resize` 80×24→120×40) + live (`resize-window -x 100 -y 30` → `stty size` reports `30 100`; restored to 80×24). Main-buffer reflow is implemented (`reflow.dart`); alt-buffer correctly unaffected. `RemoteSessionController` forwards view resize → SSH window-change (unit-tested) |
| 16 | Copy/paste | PASS (protocol) | harness: `paste()` wraps in `\x1b[200~…\x1b[201~` when app sets 2004h, raw otherwise. OS clipboard round-trip needs manual pass (platform channels) |
| 17 | Disconnect → reconnect (same tmux) | PASS | live: `sleep 60 &` started, detach simulated, `new-session -A -s still` re-attached — `jobs` shows `sleep 60` still Running, session intact. `RemoteSessionController.reconnect()` re-attaches same session (unit-tested with fakes) |
| 18 | Reattach existing tmux | PASS | live: second `new-session -A -s still` resolved to the one existing session (`tmux ls` → single entry); attach command always uses `-A` so it never duplicates |
| 19 | Multiple terminal sizes | PASS | live 80×24 → 100×30 → back, `stty size` tracked each step; attach command carries explicit `-x/-y` so first frame matches the view |
| 20 | Windows input behavior | REVIEW-ONLY (no failure found) | No Windows runner in this env. Code path is platform-independent: `TerminalView` → `keyToTerminalKey(logicalKey)` → keytab/Ctrl/Alt handlers; `dartssh2` is pure Dart (no native deps). Manual pass on a Windows build still required (notably Ctrl+C vs copy, IME) |
| 21 | Android input behavior | REVIEW-ONLY (no failure found) | No emulator booted here. `TerminalView` soft-keyboard path (`CustomTextEdit`, `deleteDetection`, `keyboardType`) is the designated mobile path and is wired in the spike. Manual pass on-device still required (notably Enter/backspace via soft keyboard, long-press selection) |

## AI-agent-critical details (explicitly checked)

- ANSI/VT: CUP/CUU/CUD/CUF/CUB, ED/EL, save/restore (`7/8`, `s/u`), margins — handled.
- DA/CPR queries (`\x1b[c`, `\x1b[6n`) answered — Ink/Claude-style apps won't hang waiting.
- OSC title sets `onTitleChange` — agent window titles work.
- Scrollback 5000 lines; 200-line stream + long-run loop — no parser failure.
- Modern sequences NOT supported but safely ignored (no crash): synchronized
  output (2026), OSC-8 hyperlinks, Kitty keyboard protocol, styled/curly
  underlines. Effect is cosmetic (possible redraw tearing in fast TUIs, links
  as plain text). None is required by Claude Code / vim / lazygit / htop / fzf
  for correct operation.
- Resize/SIGWINCH chain: view → `TerminalBackend.onResize` → SSH
  window-change → pty winsize → tmux follows; verified end-to-end for the tmux
  half live (`stty size`), SSH half by contract test.

## Failures / gaps

1. **Nothing failed.** Every executable check passed.
2. Not run live (env limits, no sudo): `nvim`, `lazygit`, `btop`, `fzf`
   binaries absent; interactive `claude` session deliberately not started;
   live `sudo` prompt not exercised. All four are covered by faithful
   synthetic sequences + (for the TUI family) real htop/less captures.
3. Manual UI passes still owed on real targets: mouse click-through,
   OS-clipboard round-trip, Windows hardware-keyboard pass, Android
   soft-keyboard pass (see rows 12/16/20/21).

## Decision

**(A) xterm.dart is good enough for the MVP.** The compatibility results do
not justify a Ghostty migration now: all agent-critical VT behavior works,
real TUI bytes parse, tmux persistence/resize/attach semantics hold, and the
unsupported sequences degrade gracefully. The `GhosttyVtAdapter` abstraction
stays as the documented future seam (`lib/src/terminal/ghostty_vt_adapter.dart`);
revisit only if real-world use shows redraw tearing, font/shaping needs, or
throughput limits that xterm.dart cannot meet.

## Blockers for workspace/UI phase

None from the terminal layer. Recommended pre-flight (not blockers): one live
`nvim` + `lazygit` pass, one Windows keyboard pass, one Android soft-keyboard
pass — all runnable from the existing spike screen with this doc's table.

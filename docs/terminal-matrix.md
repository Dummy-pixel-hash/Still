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

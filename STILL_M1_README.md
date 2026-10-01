# Still — Milestone 1 (terminal/runtime spike)

Flutter (Windows + Android) foundation. **Spike only — no workspace UI.**

## Layout

```
lib/
  main.dart                        entry
  src/app.dart                     MaterialApp -> SpikeScreen
  src/config/ssh_config.dart       host/port/user/auth/tmux/size (no secrets logged)
  src/terminal/terminal_backend.dart   ABSTRACT emulator (feed/output/onResize)
  src/terminal/xterm_backend.dart      current impl (package:xterm)
  src/terminal/ghostty_vt_adapter.dart FUTURE libghostty-vt FFI drop-in (docs)
  src/ssh/ssh_connection.dart          ABSTRACT shell channel
  src/ssh/dartssh2_connection.dart     impl (pure Dart, Win+Android safe)
  src/tmux/tmux.dart                   attach-or-create + sanitize + refresh
  src/session/remote_session_controller.dart  orchestrates SSH<->tmux<->terminal
  src/storage/credential_store.dart    secure (Keychain/Keystore/DPAPI) + memory
  src/storage/prefs_store.dart         non-secret prefs only
  src/spike/spike_screen.dart          1 form + 1 TerminalView (NOT workspace UI)
tool/verify_ssh_tmux.dart            headless SSH/tmux probe (env-driven)
docs/terminal-matrix.md              manual verification checklist
```

## Run

```sh
cd still
flutter pub get
flutter run -d windows    # or: -d emulator-5554 / physical Android
```

Then fill host/user/auth, tmux session (default `still`), **Connect**.
Remote needs OpenSSH + `tmux`.

Headless probe (no UI):

```sh
STILL_SSH_HOST=… STILL_SSH_USER=… STILL_SSH_PASSWORD=… dart run tool/verify_ssh_tmux.dart
```

## Verify

```sh
flutter analyze
flutter test
```

See `docs/terminal-matrix.md` for the 10-row checklist: shell, resize,
scroll, mouse, alt-screen TUIs (vim/htop), Unicode/truecolor, copy/paste,
disconnect/reconnect, attach-existing, auth paths.

## Ghostty path

`TerminalBackend` is the seam. `XtermBackend` proves the matrix today;
`ghostty_vt_adapter.dart` documents building `libghostty-vt` (Zig) per
target (dll/.so) + `dart:ffi` bindings + `GhosttyVtBackend implements
TerminalBackend`. Swapping changes one factory line — session/SSH/tmux/
storage untouched.

## Deliberately NOT in M1

Workspace UI (tabs, session list, settings), known_hosts TOFU UI,
multi-session, file transfer, port forwarding. Those build on
`RemoteSessionController` next.

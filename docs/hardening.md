# Still hardening notes (workspace MVP)

Concrete reliability work, not a redesign. Abstractions unchanged:
UI → SessionManager → RemoteSessionController → dartssh2 → tmux → xterm.

## Fixes landed

1. **Reattach used a stale 80×24 size.** `SessionManager._configFor`
   ignored the live view and always attached tmux at the SshConfig
   defaults, so the first frame after open/reattach was wrong-sized until
   an autoResize event corrected it. Now seeds `cols`/`rows` from the open
   backend (`test/reliability_test.dart`: sizing group).
2. **`remove()` leaked the terminal backend.** The second `_open.remove`
   always returned null, so `backend.dispose()` never ran and the manager's
   status subscription was never canceled. Now disposes controller +
   backend and cancels the subscription (regression test: removed
   backend's streams complete).
3. **Raw exception text in error UX.** Socket/SSH dumps surfaced verbatim
   in the terminal overlay. Now mapped to one calm line each
   (`session/connection_errors.dart`: wrong password/key, refused,
   unreachable/timeout, unknown host, host key, tmux missing, generic).
   Same overlay styling, no new banners or dialogs.
4. **Android backspace.** Enabled xterm's `deleteDetection` on the
   terminal view: several Android IMEs never emit a hardware delete event,
   which silently broke backspace. IME-baseline only, safe for desktop
   hardware keyboards.

## Verified by automated tests (`flutter test`, 50 passing)

- Persistence: ids distinct from display names; id + tmux handle stable
  across manager restart; fresh restart reports disconnected/unknown —
  never fake-connected.
- Lifecycle: auth failure → error state + friendly message, still
  recoverable; unexpected transport drop → disconnected/detached (remote
  survives); 3× connect/disconnect cycles consistent with one tmux
  identity; two sessions independent.
- Keys: enter/tab/escape (bare `ESC`)/backspace/delete/arrows all encode;
  Ctrl+C/D/Z correct; Escape is never swallowed by app chrome (only
  Ctrl+. and Alt+Left navigate back).
- Live tmux (isolated server, tmux 3.5a): `new-session -A -d -s <id>`
  creates once and reattaches to the single session; shell round-trips.

## Requires physical hardware (not verified here, not claimed)

- **Android device:** soft-keyboard show/hide + focus, Enter/backspace via
  Gboard/Samsung IME, OS-clipboard round-trip, rotation/viewport changes,
  touch scroll + text selection, back gesture in real navigation.
- **Windows machine:** Ctrl+. / Alt+Left with the app focused, Ctrl+C vs
  copy expectations, window resize behavior, clipboard round-trip.
  The Windows binary cannot be produced on this Linux host (MSVC
  required); `flutter build apk --debug` succeeds for Android.
- **Real SSH targets:** password/key auth failure text, unreachable-host
  timeouts, and tmux-missing remotes are covered by unit mapping only.

## Deliberately not changed

Background/foreground adds no new behavior: the transport relies on the
15 s SSH keepalive plus channel-done → disconnected mapping, so a dead
connection flips state honestly instead of showing a fake "connected".
Host-key accept-any spike behavior unchanged. No settings, key-management,
sync, accounts, or analytics UI added.

---

# Release-candidate QA (2026-10-01)

Full flow re-verified: workspace → session → SSH → tmux → fullscreen
terminal → disconnect/reconnect. `flutter analyze` clean, `flutter test`
67/67 green, `flutter build apk --debug` succeeds, `flutter build bundle`
(kernel + assets) succeeds — the strongest desktop-side signal available
on this Linux host (no clang for a Linux binary, no MSVC for Windows).

## Bugs found and fixed

1. **Workspace rebuilt its listenable every frame.** `Listenable.merge`
   was constructed inside `build`, resubscribing the `AnimatedBuilder` on
   every rebuild. Hoisted to `initState`. No leak (old merge was dropped),
   but wasteful and wrong.
2. **Redundant "Sessions" group header.** A lone ungrouped list rendered
   the serif title row plus an identical group header. Headers now appear
   only with real project grouping (widget-test pinned both ways).
3. Covered by new tests: scrollback setting sizes newly opened backends;
   remembered passwords never touch ordinary prefs; single/grouped
   header behavior.

## Re-verified, no change needed

- First launch → create → connect → terminal → back → state correct.
- Restart restores sessions/keys/settings; states fresh (never
  fake-connected); detached reattaches by stable id + tmux handle.
- Edit/rename/project/auth/key changes preserve id + tmux identity
  (tested, including across restart).
- Auth errors stay calm and human-readable (auth/refused/unreachable/
  unknown-host/hostkey/tmux-missing/generic).
- Terminal matrix from prior validation still holds (no terminal code
  changed): shell, htop/less live, alt-screen, truecolor/Unicode, mouse
  SGR, bracketed paste, Ctrl/Escape/Tab/arrows, resize/SIGWINCH, long
  runs, disconnect/reconnect.
- Every setting verified against its implementation: font size →
  `TerminalStyle`, cursor → `TerminalView.cursorType`, scrollback →
  backend `maxLines` for newly opened runtimes, confirm toggle → remove
  flow. Settings persist across restart.
- Security: no secret logging in `lib/`; PEMs only in secure storage
  (prefs scanned in tests); PEMs never rendered; removed keys/secrets
  deleted from both stores; runtime identity derives from internal id,
  never display names.
- Lifecycle: no duplicate connections (connect tears down first, UI
  guards with busy state); `remove`/dispose cancel subscriptions and
  dispose backends (tested); terminal output never routes through the
  manager, so keystrokes don't rebuild the workspace.

## Still hardware-only (unchanged, not claimed)

Physical Android IME/clipboard/rotation/touch/back-gesture, Windows
keyboard/window behavior and binary, live-SSH failure text against real
hosts. Nothing here is a code blocker.

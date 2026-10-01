import 'terminal_backend.dart';

/// Swap-in path for a Ghostty / libghostty-vt terminal emulator.
///
/// Status (Milestone 1): **documented stub, not wired**. The spike renders
/// through [XtermBackend]. This file exists so the replacement is a
/// drop-in and no session/SSH/tmux code has to change.
///
/// Why Ghostty: Ghostty's `libghostty-vt` is the VT parser + grid model
/// extracted from the Ghostty terminal. A Flutter integration means:
///   1. Build `libghostty-vt` (Zig) as a shared library per target:
///      Windows (`ghostty_vt.dll`, x64/ARM64) + Android (`.so` per ABI
///      via NDK: arm64-v8a, armeabi-v7a, x86_64).
///   2. Add a `ghostty_vt` Dart package using `dart:ffi` with bindings for:
///      create/destroy, `ghostty_vt_write`, `ghostty_vt_resize`,
///      grid snapshot + dirty-range callbacks, SGR/color/unicode attrs,
///      mouse-report encoding, alt-screen + scrollback.
///   3. Implement `GhosttyVtBackend implements TerminalBackend` on top of
///      those bindings and render the grid with a custom `RenderObject`
///      (or reuse the xterm `TerminalView` paint path initially).
///   4. Flip the factory in `RemoteSessionController` / DI to construct
///      `GhosttyVtBackend` instead of `XtermBackend`. Nothing else changes:
///      `feed`/`output`/`onResize` are the only integration points.
///
/// Suggested interface for the future backend (kept as docs, not code,
/// so we add zero native deps to the spike):
/// ```dart
/// class GhosttyVtBackend implements TerminalBackend {
///   GhosttyVtBackend({required DynamicLibrary lib, int maxLines = 50000});
///   // feed() -> ghostty_vt_write(utf8)
///   // output -> key/mouse encoders -> SSH channel
///   // onResize -> ghostty_vt_resize + SSH window-change + tmux refresh
/// }
/// ```
///
/// Until then, verification (truecolor, Unicode, alt-screen TUIs, mouse)
/// runs against xterm.dart, which covers the same VT surface.
abstract class GhosttyVtAdapter implements TerminalBackend {
  /// Factory hook reserved for the FFI backend. Throws until implemented.
  factory GhosttyVtAdapter.create() =>
      throw UnimplementedError('Ghostty/libghostty-vt FFI backend not yet '
          'integrated. See ghostty_vt_adapter.dart docs. Using XtermBackend.');
}

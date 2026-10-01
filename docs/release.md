# Still — release handoff (v1.0.0+1)

Date: 2026-10-01. Product flow: workspace → session → SSH →
persistent tmux runtime → fullscreen terminal → disconnect/reconnect.

## Metadata (verified consistent)

- Product name: **Still** (app label, window titles, version resources).
- Dart package: `still` — "Still - persistent remote sessions".
- Application ID: `dev.still.still` (Android + Linux; unchanged).
- Version: `1.0.0+1` → `versionCode 1`, `versionName 1.0.0`
  (verified inside the built APK via aapt).
- Release polish in this pass only: Android `android:label`,
  Windows title + FileDescription/ProductName, Linux window/header
  titles now read "Still". Binary/internal names stay `still`.

## Android artifacts (built here)

- APK (release): `build/app/outputs/flutter-apk/app-release.apk`
  — 24,159,520 bytes. aapt: package `dev.still.still`, label "Still",
  10 native `.so` entries (per-ABI engine + plugins).
- AAB (release): `build/app/outputs/bundle/release/app-release.aab`
  — 24,245,304 bytes. (First attempt failed on a full home disk;
  `flutter clean` reclaimed regenerable output and both rebuilt clean.)
- Signing: **debug keys** (Flutter template default). No fake
  credentials created. Configure the real keystore before any store
  or external distribution.
- Install/launch on hardware: NOT tested (no device here).

## Desktop readiness (static only — no binaries producible here)

- Windows: standard Flutter runner; CMake + manifest + version
  resources reviewed, product strings set. Requires Windows + MSVC
  to compile. Not built.
- Linux: standard GTK runner; titles + `APPLICATION_ID` reviewed.
  Requires clang++ (absent here). Not built.
- Strongest platform-independent signal obtained: `flutter build
  bundle` succeeds (Dart kernel + assets compile clean).

## Release sanity (this pass)

- No hardcoded credentials/hosts/keys in `lib/`; no `print` in `lib/`;
  no TODO/FIXME/XXX/HACK in `lib/`.
- Spike screen (`lib/src/spike/`) is dead code, unreachable from app
  navigation (default experience is workspace → terminal). Kept for
  development, per scope.
- Template TODOs in `android/app/build.gradle` (signing note) are
  boilerplate, not runtime behavior. Left alone.

## Validation status

- `flutter analyze`: No issues found.
- `flutter test`: 67/67 green.
- Full matrix in `docs/terminal-matrix.md`; reliability notes in
  `docs/hardening.md`.

## Hardware validation still required (none passed, none claimed)

Android — install/launch; soft keyboard; Gboard/Samsung behavior;
backspace/delete; Enter; Ctrl combinations; clipboard; rotation; touch
scrolling/selection; Android back gesture; terminal focus.

Windows — install/launch; keyboard shortcuts; Ctrl+.; Alt+Left; focus;
clipboard; resize; workspace ↔ terminal transition; native window
behavior.

Live SSH — authentication failure; unreachable host; timeout; refused
connection; tmux missing on remote; reconnect after transport loss.

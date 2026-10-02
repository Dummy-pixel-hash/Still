import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'session/session_manager.dart';
import 'session/still_session.dart';
import 'theme/still_theme.dart';
import 'ui/still_controls.dart';
import 'ui/terminal_screen.dart';
import 'ui/workspace_screen.dart';

/// Still workspace app. Two states, no permanent chrome:
///
/// Workspace (home) <-> Fullscreen terminal (per selected session).
///
/// The terminal grows out of the selected card (prototype card-origin
/// morph) instead of replacing the screen: the workspace stays mounted
/// behind it — scaled, dimmed, and blurred — so scroll position,
/// scrollback, and connection state all survive the trip. Navigation
/// (pill, Android back, Ctrl+., Alt+Left) and Disconnect are unchanged;
/// they only drive [SessionManager.selected].
class StillApp extends StatefulWidget {
  const StillApp({super.key, SessionManager? manager})
      : _manager = manager;

  final SessionManager? _manager;

  @override
  State<StillApp> createState() => _StillAppState();
}

enum _Phase { idle, entering, open, exiting }

class _StillAppState extends State<StillApp>
    with SingleTickerProviderStateMixin {
  late final SessionManager _manager;
  late final AnimationController _morph;
  final _workspaceKey = GlobalKey<WorkspaceScreenState>();

  StillSession? _shown;
  Rect _origin = Rect.zero;
  Rect? _pendingOrigin;
  Size _viewSize = Size.zero;
  _Phase _phase = _Phase.idle;

  @override
  void initState() {
    super.initState();
    _manager = widget._manager ?? SessionManager();
    _manager.load();
    _morph = AnimationController(vsync: this);
    _manager.addListener(_syncSelection);
    // Prototype Ctrl+K: window-level, so it works even when nothing is
    // focused. Terminal shortcuts live in the terminal itself.
    HardwareKeyboard.instance.addHandler(_globalKeys);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_globalKeys);
    _manager.removeListener(_syncSelection);
    _morph.dispose();
    if (widget._manager == null) _manager.dispose();
    super.dispose();
  }

  /// Ctrl+K focuses workspace search. Ignored while a terminal is open
  /// (the terminal owns the keyboard) and unconsumed otherwise.
  bool _globalKeys(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    if (!HardwareKeyboard.instance.isControlPressed) return false;
    if (event.logicalKey != LogicalKeyboardKey.keyK) return false;
    if (_manager.selected != null) return false;
    _workspaceKey.currentState?.focusSearch();
    return true;
  }

  /// Card-origin reported synchronously before `select()` drives this.
  void _reportOrigin(Rect origin) => _pendingOrigin = origin;

  Rect _fallbackOrigin() => Rect.fromCenter(
        center: _viewSize.center(Offset.zero),
        width: 320,
        height: 286,
      );

  void _syncSelection() {
    final selected = _manager.selected;
    if (selected != null && _shown == null && _phase == _Phase.idle) {
      _shown = selected;
      _origin = _pendingOrigin ?? _fallbackOrigin();
      _pendingOrigin = null;
      _phase = _Phase.entering;
      setState(() {});
      _morph.forward(from: 0).then((_) {
        if (!mounted) return;
        // A back-navigation during enter still exits cleanly.
        if (_manager.selected == null && _phase == _Phase.entering) {
          _beginExit();
        } else if (_phase == _Phase.entering) {
          setState(() => _phase = _Phase.open);
        }
      });
    } else if (selected == null &&
        _shown != null &&
        (_phase == _Phase.open || _phase == _Phase.entering)) {
      _beginExit();
    }
  }

  void _beginExit() {
    _phase = _Phase.exiting;
    setState(() {});
    _morph.reverse().then((_) {
      if (!mounted || _phase != _Phase.exiting) return;
      setState(() {
        _phase = _Phase.idle;
        _shown = null;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    _viewSize = MediaQuery.sizeOf(context);
    _morph.duration = StillMotion.of(context, StillMotion.morph);
    return MaterialApp(
      title: 'Still',
      theme: StillTheme.materialTheme,
      home: AnimatedBuilder(
        animation: _manager,
        builder: (context, _) {
          return Stack(
            children: [
              _workspaceBackdrop(),
              if (_shown != null)
                _terminalMorph(_shown!),
            ],
          );
        },
      ),
    );
  }

  /// Workspace stays mounted behind the terminal: scaled down, dimmed,
  /// and blurred while the morph value is above zero. Pointer and focus
  /// are held by the terminal whenever it is present.
  ///
  /// The layer structure below is UNCONDITIONAL by design: swapping
  /// wrappers in/out with the animation value would unmount and remount
  /// the entire workspace (losing scroll position and replaying card
  /// entrances). Only numeric parameters animate here — never the shape.
  Widget _workspaceBackdrop() {
    return AnimatedBuilder(
      animation: _morph,
      child: WorkspaceScreen(
        key: _workspaceKey,
        manager: _manager,
        onOpen: (session, origin) {
          _reportOrigin(origin);
          _manager.select(session.id);
        },
      ),
      builder: (context, child) {
        final v = StillMotion.ease.transform(_morph.value);
        final sigma = 8 * v;
        return IgnorePointer(
          ignoring: _shown != null,
          child: ExcludeFocus(
            excluding: _shown != null,
            child: Stack(
              children: [
                ImageFiltered(
                  imageFilter: ImageFilter.blur(
                      sigmaX: sigma, sigmaY: sigma),
                  child: Transform.scale(
                    scale: 1 - 0.035 * v,
                    alignment: Alignment.center,
                    child: child,
                  ),
                ),
                Positioned.fill(
                  child: IgnorePointer(
                    child: Opacity(
                      opacity: 0.5 * v,
                      child: Container(color: Colors.black),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// The terminal surface, lerped from the tapped card's rect to full
  /// screen. Content fades in over the second half of the morph; the
  /// card-sized frame carries a hairline ring until fully expanded.
  Widget _terminalMorph(StillSession session) {
    return AnimatedBuilder(
      animation: _morph,
      builder: (context, _) {
        final v = StillMotion.ease.transform(_morph.value);
        final full = Offset.zero & _viewSize;
        final rect = Rect.lerp(_origin, full, v) ?? full;
        final fade =
            ((_morph.value - 0.35) / 0.65).clamp(0.0, 1.0);
        return Positioned.fromRect(
          rect: rect,
          child: ClipRRect(
            borderRadius:
                BorderRadius.circular(StillTheme.cardRadius * (1 - v)),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF08080A),
                border: v < 1
                    ? Border.all(
                        color: Colors.white.withAlpha(20))
                    : null,
              ),
              child: Opacity(
                opacity: fade,
                child: TerminalScreen(
                  key: ValueKey('terminal-${session.id}'),
                  manager: _manager,
                  session: session,
                  onBack: () => _manager.select(null),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

import 'package:flutter/material.dart';

import '../theme/still_theme.dart';

/// Shared Still motion + control primitives recovered from the
/// `still-frontend` prototype (read-only reference).
///
/// Everything here is decorative or presentational: no session, SSH, or
/// storage behavior lives in this file. Hover/tilt paths are desktop-only
/// enhancements — touch layouts never depend on them.

/// Prototype easing + durations, honoring the platform reduced-motion
/// setting (animations collapse to their end state).
abstract final class StillMotion {
  /// Prototype `EASE = cubic-bezier(0.22, 1, 0.36, 1)`.
  static const Cubic ease = Cubic(0.22, 1, 0.36, 1);

  /// Prototype rise easing.
  static const Cubic riseEase = Cubic(0.2, 0.8, 0.2, 1);

  static const Duration cardEnter = Duration(milliseconds: 800);
  static const Duration morph = Duration(milliseconds: 700);
  static const Duration hover = Duration(milliseconds: 500);

  /// Zero when reduced motion is requested, [d] otherwise.
  static Duration of(BuildContext context, Duration d) =>
      MediaQuery.of(context).disableAnimations ? Duration.zero : d;
}

/// Staggered card entrance: fade + 14px rise, delayed by index.
/// Prototype: `rise 0.8s` with a 55ms per-card delay.
class RiseIn extends StatefulWidget {
  const RiseIn({super.key, required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  State<RiseIn> createState() => _RiseInState();
}

class _RiseInState extends State<RiseIn> {
  bool _visible = false;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Inherited lookups (reduced motion) are illegal in initState.
    if (_started) return;
    _started = true;
    if (StillMotion.of(context, StillMotion.cardEnter) ==
        Duration.zero) {
      _visible = true;
    } else {
      Future.delayed(Duration(milliseconds: widget.index * 55), () {
        if (mounted) setState(() => _visible = true);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      duration: StillMotion.of(context, StillMotion.cardEnter),
      curve: StillMotion.riseEase,
      opacity: _visible ? 1 : 0,
      child: AnimatedSlide(
        duration: StillMotion.of(context, StillMotion.cardEnter),
        curve: StillMotion.riseEase,
        offset: _visible ? Offset.zero : const Offset(0, 0.05),
        child: widget.child,
      ),
    );
  }
}

/// Live status dot: gentle 2.4s breathe (opacity + scale), matching the
/// prototype's `breathe` keyframes. Static when reduced motion is on.
class BreathingDot extends StatefulWidget {
  const BreathingDot({super.key});

  @override
  State<BreathingDot> createState() => _BreathingDotState();
}

class _BreathingDotState extends State<BreathingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    // Platform dispatcher (not MediaQuery) — legal in initState.
    final reducedMotion = WidgetsBinding
        .instance.platformDispatcher.accessibilityFeatures.disableAnimations;
    if (!reducedMotion) {
      _c.repeat(reverse: true);
    } else {
      _c.value = 1;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // A repeating controller never settles: only living-dot cards carry
    // one, so settled test pumps are unaffected elsewhere.
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value;
        return Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            color: StillTheme.red.withOpacity(0.55 + 0.45 * t),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                  color: StillTheme.red.withAlpha(180), blurRadius: 8),
            ],
          ),
          transformAlignment: Alignment.center,
          transform: Matrix4.identity()..scale(1 + 0.35 * t),
        );
      },
    );
  }
}

/// Desktop card atmosphere: 3D tilt toward the cursor, a soft
/// mouse-position spotlight, and the subtle red hover ring + glow.
/// Pointer-driven only — taps, long-press, and accessibility behavior of
/// [child] are untouched, and touch layouts simply never hover.
class CardAtmosphere extends StatefulWidget {
  const CardAtmosphere({super.key, required this.child});

  final Widget child;

  @override
  State<CardAtmosphere> createState() => _CardAtmosphereState();
}

class _CardAtmosphereState extends State<CardAtmosphere>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  double _mx = 0.5;
  double _my = 0;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: StillMotion.hover,
      value: 0,
    );
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _enter(PointerEvent _) => _c.forward();
  void _exit(PointerEvent _) => _c.reverse();

  void _move(PointerEvent e, BoxConstraints constraints) {
    final size = constraints.biggest;
    if (size.isEmpty) return;
    setState(() {
      _mx = (e.localPosition.dx / size.width).clamp(0.0, 1.0);
      _my = (e.localPosition.dy / size.height).clamp(0.0, 1.0);
    });
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: _enter,
      onExit: _exit,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return MouseRegion(
            opaque: false,
            onHover: (e) => _move(e, constraints),
            child: AnimatedBuilder(
              animation: _c,
              builder: (context, _) {
                final v = StillMotion.ease.transform(_c.value);
                // Prototype tilt: ±7° toward the cursor.
                const maxTilt = 7 * 3.14159265 / 180;
                final rx = (0.5 - _my) * maxTilt * v;
                final ry = (_mx - 0.5) * maxTilt * v;
                return Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()
                    ..setEntry(3, 2, 0.0011)
                    ..rotateX(rx)
                    ..rotateY(ry),
                  child: Stack(
                    children: [
                      // Red ambient glow behind the card.
                      Positioned.fill(
                        child: Opacity(
                          opacity: v,
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(
                                  StillTheme.cardRadius),
                              boxShadow: [
                                BoxShadow(
                                  color: StillTheme.red
                                      .withOpacity(0.35),
                                  blurRadius: 60,
                                  spreadRadius: -20,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      widget.child,
                      // Mouse spotlight wash.
                      Positioned.fill(
                        child: IgnorePointer(
                          child: Opacity(
                            opacity: v,
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(
                                    StillTheme.cardRadius),
                                gradient: RadialGradient(
                                  center: Alignment(
                                      _mx * 2 - 1, _my * 2 - 1),
                                  radius: 1.1,
                                  colors: [
                                    Colors.white.withOpacity(0.07),
                                    Colors.transparent,
                                  ],
                                  stops: const [0.0, 0.6],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      // Red hover ring.
                      Positioned.fill(
                        child: IgnorePointer(
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(
                                  StillTheme.cardRadius),
                              border: Border.all(
                                color: v <= 0
                                    ? Colors.transparent
                                    : StillTheme.redSoft
                                        .withOpacity(0.18 * v),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

/// Prototype primary action: red gradient pill with an inset top
/// highlight and a soft red drop shadow. Presses scale to 0.97.
class RedButton extends StatefulWidget {
  const RedButton({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback? onPressed;

  @override
  State<RedButton> createState() => _RedButtonState();
}

class _RedButtonState extends State<RedButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    return AnimatedScale(
      duration: const Duration(milliseconds: 120),
      scale: _pressed ? 0.97 : 1,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        child: InkWell(
          onTap: widget.onPressed,
          borderRadius: BorderRadius.circular(24),
          splashColor: Colors.white.withAlpha(30),
          highlightColor: Colors.transparent,
          child: Ink(
            padding:
                const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: enabled ? StillTheme.redGradient : null,
              color: enabled ? null : Colors.white.withAlpha(10),
              boxShadow: enabled
                  ? [
                      const BoxShadow(
                        color: Color.fromRGBO(255, 255, 255, 0.35),
                        offset: Offset(0, 1),
                        blurRadius: 0,
                      ),
                      BoxShadow(
                        color: StillTheme.red.withAlpha(153),
                        offset: const Offset(0, 8),
                        blurRadius: 24,
                        spreadRadius: -6,
                      ),
                    ]
                  : null,
            ),
            child: Text(
              widget.label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: enabled ? Colors.white : StillTheme.dim,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Small keyboard-hint badge (`Ctrl K`, `Ctrl .`). Desktop hint only —
/// callers gate it on wide layouts.
class Kbd extends StatelessWidget {
  const Kbd(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.white.withAlpha(26)),
      ),
      child: Text(
        label,
        style: StillTheme.mono.copyWith(
            fontSize: 9, color: StillTheme.dim),
      ),
    );
  }
}

/// Product sheet presentation: a full-bleed bottom sheet on
/// touch/narrow layouts; a centered, max-width bottom-anchored card on
/// desktop. The route stays a bottom sheet either way, so scrim
/// dismissal and keyboard insets behave exactly as before.
Future<T?> showStillSheet<T>(
  BuildContext context,
  Widget Function(BuildContext context) builder,
) {
  final wide = MediaQuery.sizeOf(context).width >= 700;
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: wide ? Colors.transparent : StillTheme.cardBottom,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    isScrollControlled: true,
    builder: (context) {
      final content = builder(context);
      if (!wide) return content;
      return Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          key: const ValueKey('still-sheet-frame'),
          constraints: const BoxConstraints(maxWidth: 480),
          child: Material(
            color: StillTheme.cardBottom,
            shape: const RoundedRectangleBorder(
              borderRadius:
                  BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: content,
          ),
        ),
      );
    },
  );
}

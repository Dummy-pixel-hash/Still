import 'package:flutter/material.dart';

import '../session/session_manager.dart';
import '../session/still_session.dart';
import '../theme/still_theme.dart';
import 'session_preview.dart';
import 'still_controls.dart';

/// A session surface: name + state, machine + kind, preview well,
/// last-active + workdir. Tap opens the fullscreen terminal.
///
/// Every card shows a visible `⋯` overflow affordance exposing the same
/// Open / Edit / Remove actions as long-press (and desktop
/// secondary-click), so the actions are discoverable without gestures.
///
/// Presence is handled by [CardAtmosphere] (desktop tilt + spotlight +
/// red hover ring) and a breathing live dot; all pointer-only effects
/// degrade to the static card on touch layouts.
class SessionCard extends StatefulWidget {
  const SessionCard({
    super.key,
    required this.session,
    required this.manager,
    required this.onOpen,
    this.onLongPress,
    this.onActions,
    this.onOrigin,
  });

  final StillSession session;
  final SessionManager manager;
  final VoidCallback onOpen;
  final VoidCallback? onLongPress;

  /// Visible-affordance entry point to the Open / Edit / Remove sheet.
  /// Falls back to [onLongPress] when null so callers can wire one
  /// callback for every discoverability path.
  final VoidCallback? onActions;

  /// Reports the card's global rect on tap / overflow / secondary-click
  /// so the app can grow the terminal out of the card. Measured from the
  /// card's own context — no GlobalKey needed.
  final void Function(Rect origin)? onOrigin;

  @override
  State<SessionCard> createState() => _SessionCardState();
}

class _SessionCardState extends State<SessionCard> {
  StillSession get session => widget.session;
  SessionManager get manager => widget.manager;

  static const _kindCommand = {
    SessionKind.shell: 'zsh',
    SessionKind.agent: 'claude',
    SessionKind.editor: 'nvim',
    SessionKind.git: 'lazygit',
    SessionKind.monitor: 'btop',
    SessionKind.logs: 'tail -f',
  };

  /// Measure this card's global rect and report it for the
  /// card→terminal morph origin. Safe to call from any card gesture:
  /// layout is always valid while the card is visible.
  void _reportOrigin() {
    final report = widget.onOrigin;
    if (report == null) return;
    final box = context.findRenderObject();
    if (box is RenderBox && box.hasSize) {
      report(box.localToGlobal(Offset.zero) & box.size);
    }
  }

  @override
  Widget build(BuildContext context) {
    final actions = widget.onActions ?? widget.onLongPress;
    final state = manager.sessionStateOf(session.id);
    final (label, dot) = switch (state) {
      SessionState.running => ('Running', const BreathingDot()),
      SessionState.detached => (
          'Detached',
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: StillTheme.faint),
            ),
          )
        ),
      SessionState.unknown => (
          'New',
          Container(
            width: 7,
            height: 7,
            decoration: const BoxDecoration(
              color: StillTheme.dim,
              shape: BoxShape.circle,
            ),
          )
        ),
    };

    return CardAtmosphere(
      child: GestureDetector(
        onTap: () {
          _reportOrigin();
          widget.onOpen();
        },
        onLongPress: widget.onLongPress,
        // Desktop discoverability: secondary-click opens the same
        // Open / Edit / Remove sheet as long-press and the overflow button.
        onSecondaryTap: actions == null
            ? null
            : () {
                _reportOrigin();
                actions();
              },
        child: Container(
          height: 286,
          padding: const EdgeInsets.all(16),
          decoration: StillTheme.cardDecoration,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      session.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: StillTheme.sans.copyWith(
                          fontSize: 15, fontWeight: FontWeight.w500),
                    ),
                  ),
                  Text(label,
                      style: StillTheme.sans
                          .copyWith(fontSize: 11, color: StillTheme.dim)),
                  const SizedBox(width: 8),
                  dot,
                  const SizedBox(width: 4),
                  SizedBox(
                    width: 28,
                    height: 28,
                    child: IconButton(
                      key: ValueKey('session-overflow-${session.id}'),
                      tooltip: 'Session actions',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    icon: const Icon(Icons.more_vert,
                        size: 18, color: StillTheme.dim),
                    onPressed: actions == null
                        ? null
                        : () {
                            _reportOrigin();
                            actions();
                          },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      session.machine,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: StillTheme.mono
                          .copyWith(fontSize: 11, color: StillTheme.faint),
                    ),
                  ),
                  Text(_kindCommand[session.kind] ?? 'zsh',
                      style: StillTheme.mono
                          .copyWith(fontSize: 10, color: StillTheme.faint)),
                ],
              ),
              const SizedBox(height: 14),
              Expanded(child: SessionPreview(session: session)),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _lastActive(session),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: StillTheme.sans
                          .copyWith(fontSize: 11, color: StillTheme.faint),
                    ),
                  ),
                  if (manager.connectionOf(session.id) ==
                      TransportState.error)
                    const Padding(
                      padding: EdgeInsets.only(right: 8),
                      child: Text('connection failed',
                          style: TextStyle(
                              fontSize: 11, color: StillTheme.redSoft)),
                    ),
                  Text(session.workdir,
                      style: StillTheme.mono
                          .copyWith(fontSize: 11, color: StillTheme.faint)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _lastActive(StillSession s) {
    final diff = DateTime.now().difference(s.lastActiveAt);
    if (manager.connectionOf(s.id) == TransportState.connected) {
      return 'Active now';
    }
    if (diff.inMinutes < 1) return 'Active just now';
    if (diff.inMinutes < 60) return 'Last active ${diff.inMinutes}m ago';
    if (diff.inHours < 24) return 'Last active ${diff.inHours}h ago';
    return 'Last active ${diff.inDays}d ago';
  }
}


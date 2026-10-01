import 'package:flutter/material.dart';

import '../session/session_manager.dart';
import '../session/still_session.dart';
import '../theme/still_theme.dart';
import 'session_preview.dart';

/// A session surface: name + state, machine + kind, preview well,
/// last-active + uptime. Tap opens the fullscreen terminal.
class SessionCard extends StatelessWidget {
  const SessionCard({
    super.key,
    required this.session,
    required this.manager,
    required this.onOpen,
    this.onLongPress,
  });

  final StillSession session;
  final SessionManager manager;
  final VoidCallback onOpen;
  final VoidCallback? onLongPress;

  static const _kindCommand = {
    SessionKind.shell: 'zsh',
    SessionKind.agent: 'claude',
    SessionKind.editor: 'nvim',
    SessionKind.git: 'lazygit',
    SessionKind.monitor: 'btop',
    SessionKind.logs: 'tail -f',
  };

  @override
  Widget build(BuildContext context) {
    final state = manager.sessionStateOf(session.id);
    final (label, dot) = switch (state) {
      SessionState.running => (
          'Running',
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: StillTheme.red,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                    color: StillTheme.red.withAlpha(180), blurRadius: 8),
              ],
            ),
          )
        ),
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

    return GestureDetector(
      onTap: onOpen,
      onLongPress: onLongPress,
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

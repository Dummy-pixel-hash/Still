import 'package:flutter/material.dart';

import 'session/session_manager.dart';
import 'theme/still_theme.dart';
import 'ui/terminal_screen.dart';
import 'ui/workspace_screen.dart';

/// Still workspace app. Two states, no permanent chrome:
///
/// Workspace (home) <-> Fullscreen terminal (per selected session).
class StillApp extends StatefulWidget {
  const StillApp({super.key, SessionManager? manager})
      : _manager = manager;

  final SessionManager? _manager;

  @override
  State<StillApp> createState() => _StillAppState();
}

class _StillAppState extends State<StillApp> {
  late final SessionManager _manager;

  @override
  void initState() {
    super.initState();
    _manager = widget._manager ?? SessionManager();
    _manager.load();
  }

  @override
  void dispose() {
    if (widget._manager == null) _manager.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Still',
      theme: StillTheme.materialTheme,
      home: AnimatedBuilder(
        animation: _manager,
        builder: (context, _) {
          final selected = _manager.selected;
          if (selected != null) {
            return TerminalScreen(
              key: ValueKey('terminal-${selected.id}'),
              manager: _manager,
              session: selected,
              onBack: () => _manager.select(null),
            );
          }
          return WorkspaceScreen(
            manager: _manager,
            onOpen: (session) => _manager.select(session.id),
          );
        },
      ),
    );
  }
}

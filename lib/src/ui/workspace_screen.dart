import 'package:flutter/material.dart';

import '../session/session_filter.dart';
import '../session/session_manager.dart';
import '../session/still_session.dart';
import '../theme/still_theme.dart';
import 'new_session_sheet.dart';
import 'session_card.dart';
import 'settings_sheet.dart';

/// The primary home. No sidebar, no nav rail: sessions are the navigation.
/// Sessions group lightly by project; the model stays Workspace ->
/// Session -> persistent remote runtime.
class WorkspaceScreen extends StatefulWidget {
  const WorkspaceScreen({
    super.key,
    required this.manager,
    required this.onOpen,
  });

  final SessionManager manager;
  final void Function(StillSession session) onOpen;

  @override
  State<WorkspaceScreen> createState() => _WorkspaceScreenState();
}

class _WorkspaceScreenState extends State<WorkspaceScreen> {
  String _query = '';
  SessionSort _sort = SessionSort.manual;
  late final Listenable _repaint;

  @override
  void initState() {
    super.initState();
    // Hoisted: building a fresh Listenable.merge on every build would
    // resubscribe the AnimatedBuilder each frame.
    _repaint =
        Listenable.merge([widget.manager, widget.manager.keys]);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _repaint,
      builder: (context, _) {
        final visible = filterAndSort(widget.manager.sessions,
            query: _query, sort: _sort);
        final groups = groupByProject(visible);
        final searching = _query.trim().isNotEmpty;
        return Scaffold(
          backgroundColor: StillTheme.ink,
          body: Stack(
            children: [
              ...StillTheme.ambientGlows(MediaQuery.sizeOf(context)),
              SafeArea(
                child: Column(
                  children: [
                    _header(context),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: _pagePadding(context),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _titleRow(
                                widget.manager.sessions.length),
                            const SizedBox(height: 20),
                            _controls(context),
                            const SizedBox(height: 24),
                            if (visible.isEmpty)
                              _emptyState(searching)
                            else if (_singleUngrouped(groups))
                              _grid(groups.single.sessions)
                            else
                              for (final g in groups) ...[
                                _groupHeader(g),
                                _grid(g.sessions),
                                const SizedBox(height: 24),
                              ],
                            const SizedBox(height: 24),
                          ],
                        ),
                      ),
                    ),
                    _footer(),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  EdgeInsets _pagePadding(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final side = w > 1400 ? 48.0 : (w > 600 ? 36.0 : 20.0);
    return EdgeInsets.fromLTRB(side, 20, side, 0);
  }

  Widget _header(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0x12FFFFFF))),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(9),
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF2A2A2E), Color(0xFF0E0E10)],
              ),
              border: Border.all(color: Colors.white.withAlpha(26)),
              boxShadow: [
                BoxShadow(
                    color: StillTheme.red.withAlpha(60), blurRadius: 24),
              ],
            ),
            child: Center(
              child: Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: StillTheme.red,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                        color: StillTheme.red.withAlpha(204), blurRadius: 10),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text('Still',
              style: StillTheme.serifTitle.copyWith(fontSize: 26)),
          Container(
              width: 1, height: 16, color: Colors.white.withAlpha(26),
              margin: const EdgeInsets.symmetric(horizontal: 12)),
          Text('Personal workspace',
              style:
                  StillTheme.sans.copyWith(fontSize: 12, color: StillTheme.dim)),
          const Spacer(),
          IconButton(
            tooltip: 'Settings',
            onPressed: () =>
                showSettingsSheet(context, widget.manager),
            icon: const Icon(Icons.settings_outlined,
                size: 19, color: StillTheme.dim),
          ),
        ],
      ),
    );
  }

  Widget _titleRow(int total) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text('Sessions',
                style:
                    StillTheme.serifTitle.copyWith(fontSize: 34)),
            const SizedBox(width: 12),
            Text(total.toString().padLeft(2, '0'),
                style: StillTheme.mono
                    .copyWith(fontSize: 13, color: StillTheme.dim)),
          ],
        ),
        const SizedBox(height: 8),
        Text('Your terminals. Right where you left them.',
            style: StillTheme.sans.copyWith(fontSize: 12, color: StillTheme.dim)),
      ],
    );
  }

  Widget _controls(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 220,
          child: TextField(
            onChanged: (v) => setState(() => _query = v),
            style: StillTheme.sans.copyWith(fontSize: 12),
            decoration: InputDecoration(
              hintText: 'Find a session',
              hintStyle: const TextStyle(
                  fontSize: 12, color: StillTheme.dim),
              prefixIcon: const Icon(Icons.search,
                  size: 14, color: StillTheme.faint),
              filled: true,
              fillColor: Colors.white.withAlpha(10),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(24),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        DropdownButton<SessionSort>(
          value: _sort,
          dropdownColor: StillTheme.chrome,
          style: StillTheme.sans.copyWith(fontSize: 12, color: StillTheme.dim),
          underline: const SizedBox.shrink(),
          items: const [
            DropdownMenuItem(
                value: SessionSort.manual, child: Text('Manual order')),
            DropdownMenuItem(
                value: SessionSort.recent, child: Text('Recently active')),
            DropdownMenuItem(
                value: SessionSort.name, child: Text('Name A–Z')),
          ],
          onChanged: (v) =>
              setState(() => _sort = v ?? SessionSort.manual),
        ),
        const SizedBox(width: 4),
        ElevatedButton(
          onPressed: () => showNewSessionSheet(context, widget.manager),
          style: ElevatedButton.styleFrom(
            backgroundColor: StillTheme.redDeep,
            foregroundColor: Colors.white,
            padding:
                const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24)),
            elevation: 8,
            shadowColor: StillTheme.red.withAlpha(120),
          ),
          child: const Text('New session', style: TextStyle(fontSize: 12)),
        ),
      ],
    );
  }

  /// A lone ungrouped list needs no header: the serif "Sessions" title
  /// row already says it. Headers appear only with real grouping.
  bool _singleUngrouped(List<SessionGroup> groups) =>
      groups.length == 1 && groups.single.title == ungroupedTitle;

  Widget _groupHeader(SessionGroup group) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Text(group.title,
              style: StillTheme.sans.copyWith(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: const Color(0xFFD3CBD4))),
          const SizedBox(width: 8),
          Text('${group.sessions.length}',
              style: StillTheme.mono
                  .copyWith(fontSize: 10, color: StillTheme.dim)),
          const SizedBox(width: 12),
          Expanded(
              child: Container(
                  height: 1, color: Colors.white.withAlpha(15))),
        ],
      ),
    );
  }

  Widget _grid(List<StillSession> sessions) {
    final w = MediaQuery.sizeOf(context).width;
    final columns = w >= 1250 ? 4 : (w >= 1000 ? 3 : (w >= 600 ? 2 : 1));
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        mainAxisExtent: 286,
      ),
      itemCount: sessions.length,
      itemBuilder: (context, i) {
        final s = sessions[i];
        return SessionCard(
          key: ValueKey(s.id),
          session: s,
          manager: widget.manager,
          onOpen: () => widget.onOpen(s),
          onLongPress: () => _cardActions(s),
        );
      },
    );
  }

  Widget _emptyState(bool searching) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Center(
        child: Column(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF2A2A2E), Color(0xFF0E0E10)],
                ),
                border: Border.all(color: Colors.white.withAlpha(26)),
              ),
              child: Center(
                child: Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: StillTheme.red,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                          color: StillTheme.red.withAlpha(180),
                          blurRadius: 12),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
                searching ? 'Nothing matches.' : 'No sessions yet.',
                style: StillTheme.sans
                    .copyWith(fontSize: 14, color: StillTheme.dim)),
            const SizedBox(height: 8),
            Text(
                searching
                    ? 'Try a different name or machine.'
                    : 'Create one to keep a terminal that never sleeps.',
                style: StillTheme.sans
                    .copyWith(fontSize: 12, color: StillTheme.faint)),
          ],
        ),
      ),
    );
  }

  Widget _footer() {
    final running = widget.manager.runningCount;
    final total = widget.manager.sessions.length;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: const BoxDecoration(
        color: Color(0xF20A090C),
        border: Border(top: BorderSide(color: Color(0x12FFFFFF))),
      ),
      child: Row(
        children: [
          Container(
              width: 4,
              height: 4,
              decoration: const BoxDecoration(
                  color: Color(0xFFB9C6AC), shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Text('$running running / $total sessions',
              style:
                  StillTheme.sans.copyWith(fontSize: 10, color: StillTheme.dim)),
          const Spacer(),
          const Text('Ctrl .  back to workspace',
              style: TextStyle(fontSize: 10, color: StillTheme.faint)),
        ],
      ),
    );
  }

  /// Long-press actions: open / edit / remove. Removal asks first when the
  /// setting is on — the remote keeps running either way.
  Future<void> _cardActions(StillSession s) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: StillTheme.cardBottom,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Text(s.name,
                style: StillTheme.serifTitle.copyWith(fontSize: 20)),
            Text(s.machine,
                style: StillTheme.mono
                    .copyWith(fontSize: 11, color: StillTheme.dim)),
            const SizedBox(height: 12),
            _action('Open', Icons.chevron_right, 'open'),
            _action('Edit', Icons.edit_outlined, 'edit'),
            _action('Remove', Icons.delete_outlined, 'remove',
                danger: true),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'open':
        widget.onOpen(s);
        break;
      case 'edit':
        await showSessionForm(context, widget.manager, initial: s);
        break;
      case 'remove':
        await _remove(s);
        break;
    }
  }

  Widget _action(String label, IconData icon, String value,
      {bool danger = false}) {
    return ListTile(
      leading: Icon(icon,
          size: 18,
          color: danger ? StillTheme.redSoft : StillTheme.dim),
      title: Text(label,
          style: StillTheme.sans.copyWith(
              fontSize: 14,
              color: danger ? StillTheme.redSoft : StillTheme.fg)),
      onTap: () => Navigator.of(context).pop(value),
    );
  }

  Future<void> _remove(StillSession s) async {
    if (widget.manager.settings.confirmBeforeRemove) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: StillTheme.cardBottom,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16)),
          title: Text('Remove session?',
              style: StillTheme.serifTitle.copyWith(fontSize: 20)),
          content: Text(
              '“${s.name}” leaves the workspace. The remote keeps running and can be reattached from a new session.',
              style: StillTheme.sans
                  .copyWith(fontSize: 13, color: StillTheme.dim)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Keep',
                  style: TextStyle(color: StillTheme.dim)),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Remove',
                  style: TextStyle(color: StillTheme.redSoft)),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    await widget.manager.remove(s.id);
  }
}

import 'package:flutter/material.dart';

import '../session/session_manager.dart';
import '../settings/app_settings.dart';
import '../theme/still_theme.dart';
import 'keys_sheet.dart';

/// Compact local-only settings. Every row maps to implemented behavior —
/// see AppSettings. No accounts, no sync, no dashboard.
Future<void> showSettingsSheet(
    BuildContext context, SessionManager manager) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: StillTheme.cardBottom,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    isScrollControlled: true,
    builder: (context) => _SettingsSheet(manager: manager),
  );
}

class _SettingsSheet extends StatelessWidget {
  const _SettingsSheet({required this.manager});

  final SessionManager manager;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: manager,
      builder: (context, _) {
        final s = manager.settings;
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.viewInsetsOf(context).bottom + 24,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Settings',
                    style: StillTheme.serifTitle.copyWith(fontSize: 24)),
                const SizedBox(height: 4),
                Text('Local to this device.',
                    style: StillTheme.sans.copyWith(
                        fontSize: 12, color: StillTheme.dim)),
                const SizedBox(height: 16),
                _section('Terminal'),
                _row(
                  'Text size',
                  trailing: Text('${s.terminalFontSize.round()}',
                      style: StillTheme.mono.copyWith(
                          fontSize: 12, color: StillTheme.dim)),
                ),
                Slider(
                  value: s.terminalFontSize,
                  min: AppSettings.minFontSize,
                  max: AppSettings.maxFontSize,
                  divisions:
                      (AppSettings.maxFontSize - AppSettings.minFontSize)
                          .round(),
                  activeColor: StillTheme.redDeep,
                  inactiveColor: Colors.white.withAlpha(20),
                  onChanged: (v) => manager.updateSettings(
                      s.copyWith(terminalFontSize: v)),
                ),
                _row('Cursor',
                    trailing: SegmentedButton<TerminalCursor>(
                      showSelectedIcon: false,
                      style: SegmentedButton.styleFrom(
                        selectedBackgroundColor:
                            StillTheme.redDeep.withAlpha(120),
                        selectedForegroundColor: StillTheme.fg,
                        foregroundColor: StillTheme.dim,
                        side: BorderSide(
                            color: Colors.white.withAlpha(20)),
                        visualDensity: VisualDensity.compact,
                      ),
                      segments: const [
                        ButtonSegment(
                            value: TerminalCursor.block, label: Text('▊')),
                        ButtonSegment(
                            value: TerminalCursor.underline,
                            label: Text('_')),
                        ButtonSegment(
                            value: TerminalCursor.bar, label: Text('¦')),
                      ],
                      selected: {s.cursor},
                      onSelectionChanged: (sel) => manager
                          .updateSettings(s.copyWith(cursor: sel.first)),
                    )),
                const SizedBox(height: 8),
                _row('Scrollback',
                    trailing: DropdownButton<int>(
                      value: s.scrollbackLines,
                      dropdownColor: StillTheme.chrome,
                      style: StillTheme.sans.copyWith(
                          fontSize: 12, color: StillTheme.dim),
                      underline: const SizedBox.shrink(),
                      items: AppSettings.scrollbackOptions
                          .map((n) => DropdownMenuItem(
                              value: n, child: Text('$n lines')))
                          .toList(),
                      onChanged: (v) => v == null
                          ? null
                          : manager.updateSettings(
                              s.copyWith(scrollbackLines: v)),
                    )),
                Text('Applies to sessions opened from now on.',
                    style: StillTheme.sans.copyWith(
                        fontSize: 10, color: StillTheme.faint)),
                const SizedBox(height: 16),
                _section('Workspace'),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('Confirm before removing',
                      style: StillTheme.sans.copyWith(fontSize: 13)),
                  subtitle: Text('Sessions keep running remotely either way.',
                      style: StillTheme.sans.copyWith(
                          fontSize: 11, color: StillTheme.dim)),
                  value: s.confirmBeforeRemove,
                  activeColor: StillTheme.redDeep,
                  onChanged: (v) => manager.updateSettings(
                      s.copyWith(confirmBeforeRemove: v)),
                ),
                const SizedBox(height: 8),
                _section('Keys'),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('SSH keys',
                      style: StillTheme.sans.copyWith(fontSize: 13)),
                  subtitle: Text(
                      '${manager.keys.keys.length} saved · this device only',
                      style: StillTheme.sans.copyWith(
                          fontSize: 11, color: StillTheme.dim)),
                  trailing: const Icon(Icons.chevron_right,
                      color: StillTheme.dim),
                  onTap: () {
                    Navigator.of(context).pop();
                    showKeysSheet(context, manager);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _section(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(title.toUpperCase(),
          style: StillTheme.mono
              .copyWith(fontSize: 10, color: StillTheme.faint)),
    );
  }

  Widget _row(String label, {required Widget trailing}) {
    return Row(
      children: [
        Expanded(
          child: Text(label,
              style: StillTheme.sans.copyWith(fontSize: 13)),
        ),
        trailing,
      ],
    );
  }
}

import 'package:flutter/material.dart';

import '../config/ssh_config.dart';
import '../session/session_manager.dart';
import '../session/still_session.dart';
import '../theme/still_theme.dart';
import 'keys_sheet.dart';

/// Restrained create/edit flow. Auth secrets are never asked here — they
/// are asked at connect time or resolved from a saved key. Editing changes
/// metadata only: `id` and `tmuxSession` are final on the model, so a
/// rename can never change the underlying runtime identity.
Future<void> showNewSessionSheet(
    BuildContext context, SessionManager manager) {
  return showSessionForm(context, manager);
}

Future<void> showSessionForm(
  BuildContext context,
  SessionManager manager, {
  StillSession? initial,
}) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: StillTheme.cardBottom,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    isScrollControlled: true,
    builder: (context) =>
        _SessionForm(manager: manager, initial: initial),
  );
}

class _SessionForm extends StatefulWidget {
  const _SessionForm({required this.manager, this.initial});

  final SessionManager manager;
  final StillSession? initial;

  @override
  State<_SessionForm> createState() => _SessionFormState();
}

class _SessionFormState extends State<_SessionForm> {
  late final TextEditingController _name;
  late final TextEditingController _host;
  late final TextEditingController _user;
  late final TextEditingController _port;
  late final TextEditingController _project;
  late SessionKind _kind;
  late SshAuthKind _auth;
  String? _keyId; // null = ask at connect time
  String? _error;

  bool get _editing => widget.initial != null;

  @override
  void initState() {
    super.initState();
    final s = widget.initial;
    _name = TextEditingController(text: s?.name ?? '');
    _host = TextEditingController(text: s?.host ?? '');
    _user = TextEditingController(text: s?.username ?? '');
    _port = TextEditingController(text: '${s?.port ?? 22}');
    _project = TextEditingController(text: s?.project ?? '');
    _kind = s?.kind ?? SessionKind.shell;
    _auth = s?.authKind ?? SshAuthKind.password;
    _keyId = s?.keyId;
  }

  @override
  void dispose() {
    _name.dispose();
    _host.dispose();
    _user.dispose();
    _port.dispose();
    _project.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final keys = widget.manager.keys.keys;
    return AnimatedBuilder(
      animation: widget.manager.keys,
      builder: (context, _) {
        final saved = widget.manager.keys.keys;
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
                Text(_editing ? 'Edit session' : 'New session',
                    style: StillTheme.serifTitle.copyWith(fontSize: 24)),
                const SizedBox(height: 4),
                Text(
                    _editing
                        ? 'Renaming never touches the running session.'
                        : 'A terminal that keeps running after you leave.',
                    style: StillTheme.sans
                        .copyWith(fontSize: 12, color: StillTheme.dim)),
                const SizedBox(height: 16),
                _field(_name, 'Name  ·  e.g. Atlas editor',
                    key: const ValueKey('session-name')),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                        child: _field(_host, 'Host  ·  e.g. dev-fra-02',
                            key: const ValueKey('session-host'))),
                    const SizedBox(width: 10),
                    SizedBox(
                        width: 80,
                        child: _field(_port, 'Port',
                            key: const ValueKey('session-port'))),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                        child: _field(_user, 'Username',
                            key: const ValueKey('session-user'))),
                    const SizedBox(width: 10),
                    Expanded(
                        child: _field(_project, 'Project  ·  e.g. Atlas',
                            key: const ValueKey('session-project'))),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<SessionKind>(
                        value: _kind,
                        dropdownColor: StillTheme.chrome,
                        decoration: _decoration('Surface'),
                        style: StillTheme.sans.copyWith(fontSize: 13),
                        items: SessionKind.values
                            .map((k) => DropdownMenuItem(
                                value: k, child: Text(k.name)))
                            .toList(),
                        onChanged: (v) =>
                            setState(() => _kind = v!),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: DropdownButtonFormField<SshAuthKind>(
                        value: _auth,
                        dropdownColor: StillTheme.chrome,
                        decoration: _decoration('Auth'),
                        style: StillTheme.sans.copyWith(fontSize: 13),
                        items: const [
                          DropdownMenuItem(
                              value: SshAuthKind.password,
                              child: Text('password')),
                          DropdownMenuItem(
                              value: SshAuthKind.privateKey,
                              child: Text('key')),
                        ],
                        onChanged: (v) =>
                            setState(() => _auth = v!),
                      ),
                    ),
                  ],
                ),
                if (_auth == SshAuthKind.privateKey) ...[
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String?>(
                    value: saved.any((k) => k.id == _keyId)
                        ? _keyId
                        : null,
                    dropdownColor: StillTheme.chrome,
                    decoration: _decoration('Saved key'),
                    style: StillTheme.sans.copyWith(fontSize: 13),
                    items: [
                      const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('Ask every time')),
                      ...saved.map((k) => DropdownMenuItem<String?>(
                          value: k.id, child: Text(k.name))),
                    ],
                    onChanged: (v) => setState(() => _keyId = v),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () =>
                          showKeysSheet(context, widget.manager),
                      child: const Text('Manage keys…',
                          style: TextStyle(
                              fontSize: 12, color: StillTheme.redSoft)),
                    ),
                  ),
                ],
                if (keys.isEmpty && _auth == SshAuthKind.privateKey)
                  const SizedBox.shrink(),
                if (_error != null) ...[
                  const SizedBox(height: 6),
                  Text(_error!,
                      style: const TextStyle(
                          fontSize: 12, color: StillTheme.redSoft)),
                ],
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: StillTheme.redDeep,
                      foregroundColor: Colors.white,
                      padding:
                          const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24)),
                    ),
                    child:
                        Text(_editing ? 'Save changes' : 'Create session'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  InputDecoration _decoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(fontSize: 12, color: StillTheme.dim),
      filled: true,
      fillColor: Colors.white.withAlpha(10),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    );
  }

  Widget _field(TextEditingController c, String hint, {Key? key}) {
    return TextField(
      key: key,
      controller: c,
      style: StillTheme.sans.copyWith(fontSize: 13),
      decoration: _decoration(hint),
    );
  }

  Future<void> _save() async {
    if (_host.text.trim().isEmpty || _user.text.trim().isEmpty) {
      setState(() => _error = 'Host and username are required.');
      return;
    }
    final port = int.tryParse(_port.text.trim()) ?? 22;
    final initial = widget.initial;
    if (initial == null) {
      final session = await widget.manager.create(
        name: _name.text,
        host: _host.text,
        username: _user.text,
        port: port,
        authKind: _auth,
        kind: _kind,
        project: _project.text,
        keyId: _auth == SshAuthKind.privateKey ? _keyId : null,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      widget.manager.select(session.id);
    } else {
      await widget.manager.update(
        initial.id,
        name: _name.text,
        host: _host.text,
        port: port,
        username: _user.text,
        authKind: _auth,
        kind: _kind,
        project: _project.text,
        keyId: () =>
            _auth == SshAuthKind.privateKey ? _keyId : null,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
    }
  }
}

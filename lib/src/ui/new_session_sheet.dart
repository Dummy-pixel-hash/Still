import 'package:flutter/material.dart';

import '../config/ssh_config.dart';
import '../session/session_manager.dart';
import '../session/session_validation.dart';
import '../session/ssh_key_store.dart';
import '../session/still_session.dart';
import '../theme/still_theme.dart';
import 'keys_sheet.dart';
import 'still_controls.dart';

/// First-time SSH flow: New session -> SSH configuration/authentication ->
/// Create & connect -> terminal.
///
/// Authentication for a *new* session is resolved here, in the form, before
/// the terminal is opened: a password, a saved key, or a key pasted for this
/// connection only. That keeps the user in one coherent place and means the
/// terminal is only entered with a usable secret. Editing an existing
/// session stays metadata-only — secrets for reconnect are handled by the
/// terminal's auth overlay, never by this form.
///
/// [initialProject] optionally prefills the Project field (e.g. from a
/// per-project `+` action). It changes no auth behavior.
Future<void> showNewSessionSheet(
  BuildContext context,
  SessionManager manager, {
  String initialProject = '',
}) {
  return showSessionForm(context, manager,
      initialProject: initialProject);
}

Future<void> showSessionForm(
  BuildContext context,
  SessionManager manager, {
  StillSession? initial,
  String initialProject = '',
}) {
  return showStillSheet(
    context,
    (context) => _SessionForm(
        manager: manager,
        initial: initial,
        initialProject: initialProject),
  );
}

class _SessionForm extends StatefulWidget {
  const _SessionForm(
      {required this.manager, this.initial, this.initialProject = ''});

  final SessionManager manager;
  final StillSession? initial;

  /// Prefills Project for brand-new sessions only; ignored when editing.
  final String initialProject;

  @override
  State<_SessionForm> createState() => _SessionFormState();
}

class _SessionFormState extends State<_SessionForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _host;
  late final TextEditingController _user;
  late final TextEditingController _port;
  late final TextEditingController _project;
  late final TextEditingController _workdir;
  late final TextEditingController _password;
  late final TextEditingController _pem;
  late SessionKind _kind;
  late SshAuthKind _auth;
  String? _keyId; // null = ask every time / paste for this connection
  bool _remember = false;
  bool _busy = false;

  bool get _editing => widget.initial != null;

  /// A saved-key id is only usable while the key still exists. A removed
  /// key degrades to "ask every time" instead of a dangling reference.
  String? _effectiveKeyId(List<SshKey> saved) {
    final id = _keyId;
    if (id == null) return null;
    return saved.any((k) => k.id == id) ? id : null;
  }

  /// True when the form names a saved key that no longer exists (removed
  /// after the session was created, or while this form is open). Shown
  /// explicitly so the missing key can never pass unnoticed.
  bool _danglingKey(List<SshKey> saved) =>
      _auth == SshAuthKind.privateKey &&
      _keyId != null &&
      !saved.any((k) => k.id == _keyId);

  @override
  void initState() {
    super.initState();
    final s = widget.initial;
    _name = TextEditingController(text: s?.name ?? '');
    _host = TextEditingController(text: s?.host ?? '');
    _user = TextEditingController(text: s?.username ?? '');
    _port = TextEditingController(text: '${s?.port ?? 22}');
    _project = TextEditingController(
        text: s?.project ?? widget.initialProject);
    _workdir = TextEditingController(text: s?.workdir ?? '~');
    _password = TextEditingController();
    _pem = TextEditingController();
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
    _workdir.dispose();
    _password.dispose();
    _pem.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.manager.keys,
      builder: (context, _) {
        final saved = widget.manager.keys.keys;
        final keyId = _effectiveKeyId(saved);
        final needsPem =
            !_editing && _auth == SshAuthKind.privateKey && keyId == null;
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.viewInsetsOf(context).bottom + 24,
          ),
          child: SingleChildScrollView(
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_editing ? 'Edit session' : 'New session',
                      style: StillTheme.serifTitle.copyWith(fontSize: 24)),
                  const SizedBox(height: 4),
                  Text(
                      _editing
                          ? 'Metadata only. Your password or key is asked when you connect.'
                          : 'Configure the machine, choose how to authenticate, '
                              'then create and connect. The remote session keeps '
                              'running; going back leaves the connection open, '
                              'Disconnect closes it.',
                      style: StillTheme.sans
                          .copyWith(fontSize: 12, color: StillTheme.dim)),
                  const SizedBox(height: 16),
                  _text(_name, 'Name  ·  e.g. Atlas editor',
                      key: const ValueKey('session-name')),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                          child: _text(_host, 'Host  ·  e.g. dev-fra-02',
                              key: const ValueKey('session-host'),
                              validator: validateSessionHost,
                              autocorrect: false)),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 80,
                        child: _text(_port, 'Port',
                            key: const ValueKey('session-port'),
                            validator: validateSessionPort,
                            keyboardType: TextInputType.number),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                          child: _text(_user, 'Username',
                              key: const ValueKey('session-user'),
                              validator: validateSessionUsername,
                              autocorrect: false)),
                      const SizedBox(width: 10),
                      Expanded(
                          child: _text(_project, 'Project  ·  e.g. Atlas',
                              key: const ValueKey('session-project'))),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _text(_workdir, 'Working directory  ·  e.g. ~/projects/atlas',
                      key: const ValueKey('session-workdir'),
                      autocorrect: false),
                  const SizedBox(height: 4),
                  const Text(
                      '“~” is home. Applies when the remote session is created.',
                      style: TextStyle(
                          fontSize: 11, color: StillTheme.faint)),
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
                          onChanged: (v) => setState(() => _kind = v!),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DropdownButtonFormField<SshAuthKind>(
                          key: const ValueKey('session-auth'),
                          value: _auth,
                          dropdownColor: StillTheme.chrome,
                          decoration: _decoration('Auth'),
                          style: StillTheme.sans.copyWith(fontSize: 13),
                          items: const [
                            DropdownMenuItem(
                                value: SshAuthKind.password,
                                child: Text('Password')),
                            DropdownMenuItem(
                                value: SshAuthKind.privateKey,
                                child: Text('SSH key')),
                          ],
                          onChanged: (v) => setState(() => _auth = v!),
                        ),
                      ),
                    ],
                  ),
                  if (_auth == SshAuthKind.password && !_editing) ...[
                    const SizedBox(height: 12),
                    _passwordField(),
                  ],
                  if (_auth == SshAuthKind.privateKey) ...[
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String?>(
                      key: const ValueKey('session-key-source'),
                      value: keyId,
                      dropdownColor: StillTheme.chrome,
                      decoration: _decoration('Key'),
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
                    if (_danglingKey(saved)) ...[
                      const SizedBox(height: 6),
                      const Text(
                        'That saved key is gone — pick another key or keep Ask every time.',
                        style: TextStyle(
                            fontSize: 11, color: StillTheme.redSoft),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Text(
                      keyId == null
                          ? (_editing
                              ? 'Ask every time — the terminal asks for your key when you connect.'
                              : 'Ask every time — use the key now without saving it. '
                                  'You\u2019ll be asked again next time you connect.')
                          : 'Saved key — unlocked from this device\u2019s secure storage at connect.',
                      style: StillTheme.sans
                          .copyWith(fontSize: 11, color: StillTheme.faint),
                    ),
                    if (needsPem) ...[
                      const SizedBox(height: 10),
                      _text(_pem, 'Private key (PEM)',
                          key: const ValueKey('session-key-pem'),
                          validator: validateSessionPem,
                          keyboardType: TextInputType.multiline,
                          minLines: 3,
                          maxLines: 5,
                          monospace: true,
                          autocorrect: false),
                    ],
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
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      key: const ValueKey('session-submit'),
                      onPressed: _busy ? null : _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: StillTheme.redDeep,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24)),
                      ),
                      child: Text(_editing
                          ? 'Save changes'
                          : (_busy ? 'Creating…' : 'Create & connect')),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Host identity isn’t verified yet — Still accepts any host key. Only connect to machines you trust.',
                    textAlign: TextAlign.center,
                    style:
                        TextStyle(fontSize: 11, color: StillTheme.faint),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _passwordField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _text(_password, 'Password',
            key: const ValueKey('session-password'),
            validator: validateSessionPassword,
            obscureText: true),
        Row(
          children: [
            Checkbox(
              key: const ValueKey('session-remember'),
              value: _remember,
              activeColor: StillTheme.redDeep,
              onChanged: (v) => setState(() => _remember = v ?? false),
            ),
            const Expanded(
              child: Text('Remember on this device',
                  style: TextStyle(fontSize: 12, color: StillTheme.dim)),
            ),
          ],
        ),
      ],
    );
  }

  InputDecoration _decoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(fontSize: 12, color: StillTheme.dim),
      filled: true,
      fillColor: Colors.white.withAlpha(10),
      errorStyle: const TextStyle(fontSize: 11, color: StillTheme.redSoft),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    );
  }

  Widget _text(
    TextEditingController c,
    String hint, {
    Key? key,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
    bool obscureText = false,
    bool autocorrect = true,
    bool monospace = false,
    int minLines = 1,
    int maxLines = 1,
  }) {
    return TextFormField(
      key: key,
      controller: c,
      validator: validator,
      keyboardType: keyboardType,
      obscureText: obscureText,
      autocorrect: autocorrect,
      enableSuggestions: autocorrect,
      minLines: minLines,
      maxLines: maxLines,
      style: StillTheme.sans.copyWith(
          fontSize: 13, fontFamily: monospace ? 'monospace' : null),
      decoration: _decoration(hint),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final port = tryParseSessionPort(_port.text);
    if (port == null) return; // validator already surfaced the problem
    final keyId = _effectiveKeyId(widget.manager.keys.keys);
    final initial = widget.initial;

    if (initial == null) {
      setState(() => _busy = true);
      final session = await widget.manager.create(
        name: _name.text,
        host: _host.text,
        username: _user.text,
        port: port,
        authKind: _auth,
        kind: _kind,
        workdir: _workdir.text,
        project: _project.text,
        keyId: _auth == SshAuthKind.privateKey ? keyId : null,
      );
      // Resolve auth *before* opening the terminal. Password and a
      // one-off key are staged in memory; a saved key is resolved by the
      // manager from secure storage. Either way the terminal enters with a
      // usable secret, never an empty one.
      if (_auth == SshAuthKind.password) {
        await widget.manager
            .stageSecret(session, _password.text, remember: _remember);
      } else if (keyId == null) {
        await widget.manager.stageSecret(session, _pem.text);
      }
      if (!mounted) return;
      Navigator.of(context).pop();
      widget.manager.select(session.id);
    } else {
      setState(() => _busy = true);
      await widget.manager.update(
        initial.id,
        name: _name.text,
        host: _host.text,
        port: port,
        username: _user.text,
        authKind: _auth,
        kind: _kind,
        workdir: _workdir.text,
        project: _project.text,
        keyId: () =>
            _auth == SshAuthKind.privateKey ? keyId : null,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
    }
  }
}

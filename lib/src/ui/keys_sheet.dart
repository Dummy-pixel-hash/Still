import 'package:flutter/material.dart';

import '../session/session_manager.dart';
import '../session/ssh_key_store.dart';
import '../theme/still_theme.dart';
import 'still_controls.dart';

/// Local SSH key management. Names live in prefs, key material only in
/// secure storage. PEM contents are never displayed — only names.
/// No cloud sync.
Future<void> showKeysSheet(
    BuildContext context, SessionManager manager) {
  return showStillSheet(
    context,
    (context) => _KeysSheet(keys: manager.keys),
  );
}

class _KeysSheet extends StatefulWidget {
  const _KeysSheet({required this.keys});

  final SshKeyStore keys;

  @override
  State<_KeysSheet> createState() => _KeysSheetState();
}

class _KeysSheetState extends State<_KeysSheet> {
  bool _adding = false;
  final _name = TextEditingController();
  final _pem = TextEditingController();
  final _passphrase = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _pem.dispose();
    _passphrase.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.keys,
      builder: (context, _) {
        final keys = widget.keys.keys;
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
                Text('SSH keys',
                    style: StillTheme.serifTitle.copyWith(fontSize: 24)),
                const SizedBox(height: 4),
                Text(
                    'Stored on this device only. Keys are referenced by name, never shown.',
                    style: StillTheme.sans.copyWith(
                        fontSize: 12, color: StillTheme.dim)),
                const SizedBox(height: 16),
                if (keys.isEmpty && !_adding)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text('No saved keys yet.',
                        style: StillTheme.sans.copyWith(
                            fontSize: 13, color: StillTheme.dim)),
                  ),
                for (final key in keys) _keyRow(key),
                if (_adding) ...[
                  const SizedBox(height: 12),
                  _addForm(),
                ] else ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () {
                        _adding = true;
                        _error = null;
                        setState(() {});
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: StillTheme.fg,
                        side: BorderSide(
                            color: Colors.white.withAlpha(30)),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20)),
                        padding:
                            const EdgeInsets.symmetric(vertical: 13),
                      ),
                      child: const Text('Add a key'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _keyRow(SshKey key) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Colors.white.withAlpha(8),
        border: Border.all(color: Colors.white.withAlpha(12)),
      ),
      child: Row(
        children: [
          const Icon(Icons.key_outlined,
              size: 16, color: StillTheme.dim),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(key.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: StillTheme.sans.copyWith(fontSize: 13)),
                Text(_date(key),
                    style: StillTheme.mono.copyWith(
                        fontSize: 10, color: StillTheme.faint)),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Rename key',
            onPressed: () => _rename(key),
            icon: const Icon(Icons.edit_outlined,
                size: 16, color: StillTheme.dim),
          ),
          IconButton(
            tooltip: 'Remove key',
            onPressed: () => _remove(key),
            icon: const Icon(Icons.delete_outlined,
                size: 16, color: StillTheme.dim),
          ),
        ],
      ),
    );
  }

  String _date(SshKey key) {
    final c = key.createdAt;
    return 'added ${c.year}-${c.month.toString().padLeft(2, '0')}-${c.day.toString().padLeft(2, '0')}';
  }

  Widget _addForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _field(_name, 'Name  ·  e.g. laptop ed25519'),
        const SizedBox(height: 10),
        _field(_pem, 'Private key (PEM)', mono: true, lines: 5),
        const SizedBox(height: 10),
        _field(_passphrase, 'Passphrase (optional)', obscure: true),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!,
              style: const TextStyle(
                  fontSize: 12, color: StillTheme.redSoft)),
        ],
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _busy
                    ? null
                    : () {
                        _pem.clear();
                        _passphrase.clear();
                        setState(() {
                          _adding = false;
                          _error = null;
                        });
                      },
                style: OutlinedButton.styleFrom(
                  foregroundColor: StillTheme.dim,
                  side:
                      BorderSide(color: Colors.white.withAlpha(30)),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20)),
                ),
                child: const Text('Cancel'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton(
                onPressed: _busy ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: StillTheme.redDeep,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20)),
                ),
                child: const Text('Save key'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _field(TextEditingController c, String hint,
      {bool mono = false, bool obscure = false, int lines = 1}) {
    return TextField(
      controller: c,
      obscureText: obscure,
      maxLines: obscure ? 1 : lines,
      minLines: obscure ? 1 : (lines > 1 ? 3 : 1),
      style: StillTheme.sans.copyWith(
          fontSize: 13,
          fontFamily: mono ? 'monospace' : null),
      decoration: InputDecoration(
        labelText: hint,
        labelStyle:
            const TextStyle(fontSize: 12, color: StillTheme.dim),
        filled: true,
        fillColor: Colors.white.withAlpha(10),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    );
  }

  Future<void> _save() async {
    if (_pem.text.trim().isEmpty) {
      setState(() => _error = 'Paste the private key first.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.keys.add(
        name: _name.text,
        pem: _pem.text,
        passphrase:
            _passphrase.text.isEmpty ? null : _passphrase.text,
      );
      // Clear secret material from memory immediately.
      _name.clear();
      _pem.clear();
      _passphrase.clear();
      if (!mounted) return;
      setState(() {
        _adding = false;
        _busy = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Couldn\u2019t save that key. Check the format.';
        });
      }
    }
  }

  Future<void> _rename(SshKey key) async {
    final c = TextEditingController(text: key.name);
    final next = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: StillTheme.cardBottom,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: Text('Rename key',
            style: StillTheme.serifTitle.copyWith(fontSize: 20)),
        content: TextField(
          controller: c,
          autofocus: true,
          style: StillTheme.sans.copyWith(fontSize: 13),
          decoration: const InputDecoration(
            filled: true,
            fillColor: Color(0x1AFFFFFF),
            border: OutlineInputBorder(borderSide: BorderSide.none),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel',
                style: TextStyle(color: StillTheme.dim)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(c.text),
            child: const Text('Save',
                style: TextStyle(color: StillTheme.redSoft)),
          ),
        ],
      ),
    );
    c.dispose();
    if (next != null && next.trim().isNotEmpty) {
      await widget.keys.rename(key.id, next);
    }
  }

  Future<void> _remove(SshKey key) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: StillTheme.cardBottom,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: Text('Remove key?',
            style: StillTheme.serifTitle.copyWith(fontSize: 20)),
        content: Text(
            '“${key.name}” stops working for any session using it. Sessions themselves are untouched.',
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
    if (ok == true) await widget.keys.remove(key.id);
  }
}

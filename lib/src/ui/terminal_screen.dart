import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart';

import '../session/connection_errors.dart';
import '../session/session_manager.dart';
import '../session/still_session.dart';
import '../settings/app_settings.dart';
import '../theme/still_theme.dart';

/// Fullscreen terminal. The terminal owns the viewport; chrome is a single
/// auto-hiding pill. Back: Ctrl+. / Alt+Left on desktop, system back on
/// Android (PopScope), pill button everywhere.
class TerminalScreen extends StatefulWidget {
  const TerminalScreen({
    super.key,
    required this.manager,
    required this.session,
    required this.onBack,
  });

  final SessionManager manager;
  final StillSession session;
  final VoidCallback onBack;

  @override
  State<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends State<TerminalScreen> {
  final _secret = TextEditingController();
  bool _remember = false;
  bool _busy = false;
  bool _chrome = true;
  Timer? _hideTimer;
  String? _localError;

  @override
  void initState() {
    super.initState();
    widget.manager.open(widget.session.id);
    _maybeAutoConnect();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _secret.dispose();
    super.dispose();
  }

  /// If a secret is already known (memory or secure storage), connect
  /// straight away so opening a card lands in a live terminal.
  Future<void> _maybeAutoConnect() async {
    if (widget.manager.connectionOf(widget.session.id) ==
        TransportState.connected) {
      _scheduleHide();
      return;
    }
    // Try stored-secret connect without prompting.
    setState(() => _busy = true);
    try {
      await widget.manager.connect(widget.session);
    } catch (_) {
      // No stored secret or unreachable: fall through to the auth overlay.
      // Error text surfaces via manager.errorOf + local state stays calm.
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _scheduleHide();
      }
    }
  }

  void _scheduleHide([int ms = 3500]) {
    _hideTimer?.cancel();
    _hideTimer = Timer(Duration(milliseconds: ms), () {
      if (!mounted) return;
      final live = widget.manager.connectionOf(widget.session.id) ==
          TransportState.connected;
      if (live) setState(() => _chrome = false);
    });
  }

  void _pokeChrome() {
    setState(() => _chrome = true);
    _scheduleHide(2200);
  }

  Future<void> _connect() async {
    setState(() {
      _busy = true;
      _localError = null;
    });
    try {
      await widget.manager.connect(
        widget.session,
        secret: _secret.text,
        remember: _remember,
      );
      _secret.clear();
    } catch (e) {
      setState(() => _localError = friendlyConnectionError(e));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _scheduleHide();
      }
    }
  }

  Future<void> _reconnect() async {
    setState(() {
      _busy = true;
      _localError = null;
    });
    try {
      await widget.manager.reconnect(widget.session.id);
    } catch (e) {
      setState(() => _localError = friendlyConnectionError(e));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _scheduleHide();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final runtime = widget.manager.open(widget.session.id);
    final session = widget.session;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) widget.onBack();
      },
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.period, control: true):
              widget.onBack,
          const SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true):
              widget.onBack,
        },
        child: Focus(
          autofocus: true,
          child: AnimatedBuilder(
            animation: widget.manager,
            builder: (context, _) {
              final conn =
                  widget.manager.connectionOf(session.id);
              final live = conn == TransportState.connected;
              return Scaffold(
                backgroundColor: const Color(0xFF08080A),
                body: MouseRegion(
                  onHover: (e) {
                    if (e.position.dy < 64) _pokeChrome();
                  },
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: TerminalView(
                          runtime.backend.terminal,
                          autofocus: true,
                          textStyle: TerminalStyle(
                              fontSize: widget
                                  .manager.settings.terminalFontSize),
                          cursorType: switch (widget
                              .manager.settings.cursor) {
                            TerminalCursor.block =>
                              TerminalCursorType.block,
                            TerminalCursor.underline =>
                              TerminalCursorType.underline,
                            TerminalCursor.bar =>
                              TerminalCursorType.verticalBar,
                          },
                          // Recommended by xterm.dart for mobile: several
                          // Android IMEs never emit a hardware delete event,
                          // which silently breaks backspace. This only changes
                          // the IME baseline, not rendered content, so it is
                          // safe to leave on for desktop hardware keyboards.
                          deleteDetection: true,
                          padding: const EdgeInsets.only(
                              top: 8, left: 8, right: 8, bottom: 8),
                        ),
                      ),
                      if (!live) _overlay(conn, session),
                      _chromePill(session, conn, live),
                      if (live && !_chrome)
                        Positioned(
                          top: MediaQuery.paddingOf(context).top + 8,
                          left: 8,
                          child: _ghostBack(),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _ghostBack() {
    return GestureDetector(
      onTap: widget.onBack,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: StillTheme.chrome.withAlpha(160),
          border: Border.all(color: Colors.white.withAlpha(20)),
        ),
        child: const Icon(Icons.chevron_left,
            size: 20, color: StillTheme.dim),
      ),
    );
  }

  Widget _chromePill(
      StillSession session, TransportState conn, bool live) {
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
      top: _chrome
          ? MediaQuery.paddingOf(context).top + 10
          : MediaQuery.paddingOf(context).top - 60,
      left: 0,
      right: 0,
      child: Center(
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 300),
          opacity: _chrome ? 1 : 0,
          child: Container(
            padding: const EdgeInsets.only(left: 16, right: 6, top: 6, bottom: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              color: StillTheme.chrome.withAlpha(220),
              border: Border.all(color: Colors.white.withAlpha(23)),
              boxShadow: const [
                BoxShadow(
                    color: Color.fromRGBO(0, 0, 0, 0.7),
                    blurRadius: 40,
                    offset: Offset(0, 16)),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('›_',
                    style: TextStyle(
                        fontFamily: 'monospace', color: StillTheme.dim)),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(session.name,
                      overflow: TextOverflow.ellipsis,
                      style: StillTheme.sans.copyWith(
                          fontSize: 12, fontWeight: FontWeight.w500)),
                ),
                const SizedBox(width: 8),
                Text(session.host,
                    style: StillTheme.mono
                        .copyWith(fontSize: 11, color: StillTheme.dim)),
                const SizedBox(width: 4),
                _statusDot(conn),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: widget.onBack,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      color: Colors.white.withAlpha(18),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Workspace',
                            style: TextStyle(
                                fontSize: 12, color: StillTheme.fg)),
                        const SizedBox(width: 8),
                        Text(!live ? '' : 'Ctrl .',
                            style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 10,
                                color: StillTheme.faint)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _statusDot(TransportState conn) {
    switch (conn) {
      case TransportState.connected:
        return Container(
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
        );
      case TransportState.connecting:
        return const SizedBox(
          width: 10,
          height: 10,
          child: CircularProgressIndicator(
              strokeWidth: 2, color: StillTheme.redSoft),
        );
      case TransportState.error:
        return Container(
            width: 7,
            height: 7,
            decoration: const BoxDecoration(
                color: StillTheme.redSoft, shape: BoxShape.circle));
      case TransportState.disconnected:
        return Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: StillTheme.faint)),
        );
    }
  }

  /// Auth / reconnect overlay. Terminal stays mounted underneath so
  /// scrollback survives; the overlay is a dimmed sheet, not a route.
  Widget _overlay(TransportState conn, StillSession session) {
    final storedError =
        widget.manager.errorOf(session.id) ?? _localError;
    final needsSecret = conn != TransportState.connecting &&
        widget.manager.runtimeOf(session.id) != RuntimeState.ready;

    return Positioned.fill(
      child: Container(
        color: Colors.black.withAlpha(150),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 380),
              padding: const EdgeInsets.all(22),
              decoration: StillTheme.cardDecoration,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(session.name,
                      style:
                          StillTheme.serifTitle.copyWith(fontSize: 22)),
                  const SizedBox(height: 4),
                  Text(session.machine,
                      style: StillTheme.mono
                          .copyWith(fontSize: 12, color: StillTheme.dim)),
                  const SizedBox(height: 16),
                  if (conn == TransportState.connecting ||
                      conn == TransportState.error && _busy)
                    const Row(
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: StillTheme.redSoft),
                        ),
                        SizedBox(width: 12),
                        Text('Connecting…',
                            style: TextStyle(
                                fontSize: 13, color: StillTheme.dim)),
                      ],
                    )
                  else if (needsSecret)
                    ..._authFields(session),
                  if (storedError != null && !_busy) ...[
                    const SizedBox(height: 12),
                    Text(storedError,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 11, color: StillTheme.redSoft)),
                  ],
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _busy ? null : widget.onBack,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: StillTheme.dim,
                            side: BorderSide(
                                color: Colors.white.withAlpha(30)),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20)),
                          ),
                          child: const Text('Workspace'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _busy
                              ? null
                              : (widget.manager.sessionStateOf(
                                              session.id) ==
                                          SessionState.detached ||
                                      storedError != null
                                  ? _reconnectOrConnect
                                  : _connect),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: StillTheme.redDeep,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20)),
                          ),
                          child: Text(
                              widget.manager.sessionStateOf(session.id) ==
                                      SessionState.detached
                                  ? 'Reattach'
                                  : 'Connect'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Disconnecting never stops the remote session — it keeps running and reattaches here.',
                    style:
                        TextStyle(fontSize: 10, color: StillTheme.faint),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _authFields(StillSession session) {
    final isKey = session.authKind.name == 'privateKey';
    return [
      TextField(
        controller: _secret,
        obscureText: !isKey,
        maxLines: isKey ? 4 : 1,
        minLines: isKey ? 3 : 1,
        onSubmitted: (_) => _connect(),
        style: StillTheme.sans.copyWith(
            fontSize: 13,
            fontFamily: isKey ? 'monospace' : null),
        decoration: InputDecoration(
          labelText: isKey ? 'Private key (PEM)' : 'Password',
          labelStyle:
              const TextStyle(fontSize: 12, color: StillTheme.dim),
          filled: true,
          fillColor: Colors.white.withAlpha(10),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none),
        ),
      ),
      const SizedBox(height: 8),
      Row(
        children: [
          Checkbox(
              value: _remember,
              activeColor: StillTheme.redDeep,
              onChanged: (v) => setState(() => _remember = v ?? false)),
          const Expanded(
            child: Text('Remember on this device',
                style: TextStyle(fontSize: 12, color: StillTheme.dim)),
          ),
        ],
      ),
    ];
  }

  Future<void> _reconnectOrConnect() async {
    // Detached sessions prefer secret-based connect (fresh channel +
    // explicit tmux attach); pure reattach is the fallback inside
    // SessionManager.reconnect when no secret is known.
    if (_secret.text.isNotEmpty) {
      return _connect();
    }
    return _reconnect();
  }
}

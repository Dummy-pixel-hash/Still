/// tmux persistence helpers.
///
/// Strategy (Milestone 1): attach-or-create with explicit size so the remote
/// side matches the local emulator from the first frame:
///   `tmux -u new-session -A -s <name> -x <cols> -y <rows>`
/// `-u` forces UTF-8, `-A` attaches if the session exists else creates it.
/// Resize path: SSH window-change (pty) + `tmux refresh-client -t <name>
/// -x <cols> -y <rows>` fallback for servers that need an explicit hint.
/// Reconnect == open a fresh shell and re-run the same attach command, which
/// is why tmux sessions survive network drops.
class TmuxPlan {
  const TmuxPlan({required this.sessionName});

  final String sessionName;

  static final _unsafe = RegExp(r'[^A-Za-z0-9_\-.]');

  /// tmux session names are matched exactly; sanitize user input so the
  /// attach command cannot inject extra shell.
  static String sanitizeName(String raw) {
    final name = raw.trim();
    if (name.isEmpty) return 'still';
    return name.replaceAll(_unsafe, '_');
  }

  /// Command written to the fresh shell to enter (or create) the session.
  /// Executed via `exec` so disconnecting the shell does not kill tmux.
  ///
  /// [startDirectory]: empty or `~` omits `-c` (login default, i.e. home);
  /// anything else becomes `tmux -c`, which sets the working directory
  /// only when the session is created — attaching to an existing session
  /// never moves it. [startCommand] is an allowlisted creation command
  /// (see `startCommandFor`), likewise creation-only. Both cross the
  /// remote shell, so the directory is quoted; the command is a fixed
  /// string, never user input.
  String attachCommand({
    int cols = 80,
    int rows = 24,
    String startDirectory = '',
    String startCommand = '',
  }) {
    final name = sanitizeName(sessionName);
    final buf = StringBuffer('tmux -u new-session -A -s $name');
    final dir = startDirectory.trim();
    if (dir.isNotEmpty && dir != '~') {
      buf.write(' -c ${shQuotePath(dir)}');
    }
    final cmd = startCommand.trim();
    if (cmd.isNotEmpty) buf.write(' $cmd');
    buf.write(' -x $cols -y $rows\n');
    return buf.toString();
  }

  /// Quote a string for POSIX sh: `a'b` -> `'a'\''b'`.
  static String shQuote(String raw) =>
      "'${raw.replaceAll("'", "'\\''")}'";

  /// Quote a path, preserving a leading `~` (or `~user`) unquoted so the
  /// remote shell still expands it to a home directory.
  static String shQuotePath(String raw) {
    final match = RegExp(r'^~[^/]*').firstMatch(raw);
    if (match == null) return shQuote(raw);
    return '${match.group(0)}${shQuote(raw.substring(match.end))}';
  }

  /// Sent after an SSH-level resize so tmux redraws to the new geometry.
  String refreshCommand({required int cols, required int rows}) {
    final name = sanitizeName(sessionName);
    // Best-effort: ignored when the client is not yet inside tmux.
    return 'tmux refresh-client -t $name -x $cols -y $rows 2>/dev/null\n';
  }

  String get listCommand => 'tmux ls\n';
}

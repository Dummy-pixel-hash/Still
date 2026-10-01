/// Local-only MVP settings. Every option maps to real implemented
/// behavior (no decorative toggles):
/// - terminal font size -> TerminalView text style
/// - cursor style -> TerminalView cursor type
/// - scrollback lines -> XtermBackend maxLines for newly opened runtimes
/// - confirm before remove -> workspace remove flow
enum TerminalCursor { block, underline, bar }

class AppSettings {
  const AppSettings({
    this.terminalFontSize = 13,
    this.cursor = TerminalCursor.block,
    this.scrollbackLines = 5000,
    this.confirmBeforeRemove = true,
  });

  final double terminalFontSize;
  final TerminalCursor cursor;
  final int scrollbackLines;
  final bool confirmBeforeRemove;

  static const minFontSize = 10.0;
  static const maxFontSize = 20.0;
  static const scrollbackOptions = [1000, 5000, 20000];

  AppSettings copyWith({
    double? terminalFontSize,
    TerminalCursor? cursor,
    int? scrollbackLines,
    bool? confirmBeforeRemove,
  }) {
    return AppSettings(
      terminalFontSize: (terminalFontSize ?? this.terminalFontSize)
          .clamp(minFontSize, maxFontSize),
      cursor: cursor ?? this.cursor,
      scrollbackLines: scrollbackOptions.contains(scrollbackLines)
          ? scrollbackLines!
          : this.scrollbackLines,
      confirmBeforeRemove: confirmBeforeRemove ?? this.confirmBeforeRemove,
    );
  }

  Map<String, Object?> toJson() => {
        'terminalFontSize': terminalFontSize,
        'cursor': cursor.name,
        'scrollbackLines': scrollbackLines,
        'confirmBeforeRemove': confirmBeforeRemove,
      };

  factory AppSettings.fromJson(Map<String, Object?> json) {
    return AppSettings(
      terminalFontSize:
          ((json['terminalFontSize'] as num?)?.toDouble() ?? 13)
              .clamp(minFontSize, maxFontSize),
      cursor: TerminalCursor.values.asNameMap()[json['cursor']] ??
          TerminalCursor.block,
      scrollbackLines:
          (json['scrollbackLines'] as num?)?.toInt() ?? 5000,
      confirmBeforeRemove:
          (json['confirmBeforeRemove'] as bool?) ?? true,
    ).copyWith();
  }
}

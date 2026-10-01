import 'still_session.dart';

/// Workspace list logic, kept pure for tests. The mental model stays:
/// Workspace -> Session -> persistent remote runtime.
///
/// Sessions with an empty project live under [ungroupedTitle].
enum SessionSort { manual, recent, name }

const ungroupedTitle = 'Sessions';

/// Filter by query (name + machine), then sort. Manual keeps creation order.
List<StillSession> filterAndSort(
  List<StillSession> sessions, {
  String query = '',
  SessionSort sort = SessionSort.manual,
}) {
  final q = query.trim().toLowerCase();
  var list = q.isEmpty
      ? List<StillSession>.from(sessions)
      : sessions
          .where((s) =>
              '${s.name} ${s.machine}'.toLowerCase().contains(q))
          .toList();
  switch (sort) {
    case SessionSort.recent:
      list.sort((a, b) => b.lastActiveAt.compareTo(a.lastActiveAt));
      break;
    case SessionSort.name:
      list.sort((a, b) =>
          a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      break;
    case SessionSort.manual:
      break;
  }
  return list;
}

/// Group into named sections. Named projects first (A-Z), then the
/// ungrouped sessions. Empty input yields no groups.
List<SessionGroup> groupByProject(List<StillSession> sessions) {
  final named = <String, List<StillSession>>{};
  final ungrouped = <StillSession>[];
  for (final s in sessions) {
    final project = s.project.trim();
    if (project.isEmpty) {
      ungrouped.add(s);
    } else {
      named.putIfAbsent(project, () => []).add(s);
    }
  }
  final groups = named.entries
      .map((e) => SessionGroup(title: e.key, sessions: e.value))
      .toList()
    ..sort((a, b) =>
        a.title.toLowerCase().compareTo(b.title.toLowerCase()));
  if (ungrouped.isNotEmpty || groups.isEmpty) {
    groups.add(SessionGroup(title: ungroupedTitle, sessions: ungrouped));
  }
  return groups;
}

class SessionGroup {
  const SessionGroup({required this.title, required this.sessions});

  final String title;
  final List<StillSession> sessions;
}

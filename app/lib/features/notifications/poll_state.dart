import '../../core/routing/routes.dart';
import '../../data/github/models/models.dart';

/// What the poller remembers about one watched repo between checks.
class RepoPollState {
  RepoPollState({Map<String, String>? branches, Map<int, PullSnapshot>? pulls, this.checkedAt})
    : branches = branches ?? {},
      pulls = pulls ?? {};

  factory RepoPollState.fromJson(Map<String, dynamic> j) => RepoPollState(
    branches: (j['b'] as Map<String, dynamic>? ?? const {}).cast<String, String>(),
    pulls: {
      for (final e in (j['p'] as Map<String, dynamic>? ?? const {}).entries)
        int.parse(e.key): PullSnapshot.fromJson(e.value as Map<String, dynamic>),
    },
    checkedAt: DateTime.tryParse(j['t'] as String? ?? ''),
  );

  /// Branch name → head SHA.
  final Map<String, String> branches;

  /// PR number → last seen state.
  final Map<int, PullSnapshot> pulls;

  /// Null until the first (silent, seeding) check has completed.
  DateTime? checkedAt;

  bool get isSeeded => checkedAt != null;

  Map<String, dynamic> toJson() => {
    'b': branches,
    'p': {for (final e in pulls.entries) '${e.key}': e.value.toJson()},
    't': checkedAt?.toIso8601String(),
  };
}

class PullSnapshot {
  const PullSnapshot({required this.state, required this.draft});

  factory PullSnapshot.of(GhPull p) =>
      PullSnapshot(state: p.state == PullState.draft ? PullState.open : p.state, draft: p.state == PullState.draft);

  factory PullSnapshot.fromJson(Map<String, dynamic> j) =>
      PullSnapshot(state: PullState.values.byName(j['s'] as String), draft: j['d'] as bool? ?? false);

  /// open / closed / merged (draft is tracked separately).
  final PullState state;
  final bool draft;

  Map<String, dynamic> toJson() => {'s': state.name, 'd': draft};
}

/// A notification-worthy event.
class GitEvent {
  const GitEvent({required this.title, required this.body, required this.route, required this.tag});

  final String title;
  final String body;

  /// In-app route opened when the notification is tapped.
  final String route;

  /// Stable identity; the same tag replaces rather than duplicates a notification.
  final String tag;

  int get notificationId => tag.hashCode & 0x7fffffff;

  @override
  String toString() => 'GitEvent($title | $body → $route)';
}

/// A branch whose head moved since the last check.
typedef BranchMove = ({String branch, String? from, String to});

/// Branches that are new or whose head changed. Deleted branches are ignored.
List<BranchMove> diffBranches(Map<String, String> before, List<GhBranch> now) => [
  for (final b in now)
    if (before[b.name] != b.sha) (branch: b.name, from: before[b.name], to: b.sha),
];

bool isBotLogin(String? login) => login != null && login.toLowerCase().endsWith('[bot]');

/// PR lifecycle events between two snapshots: opened, ready for review,
/// reopened, merged. Plain closes and edits don't notify.
List<GitEvent> pullEvents(
  RepoRef repo,
  Map<int, PullSnapshot> before,
  List<GhPull> now, {
  required DateTime since,
  String? selfLogin,
}) {
  final out = <GitEvent>[];
  for (final p in now) {
    final prev = before[p.number];
    final author = p.author.login;
    final isSelf = selfLogin != null && author.toLowerCase() == selfLogin.toLowerCase();
    String? verb;
    if (prev == null) {
      // Unknown PR: only "new" if it was created after the last check.
      if (p.createdAt.isAfter(since)) {
        verb = switch (p.state) {
          PullState.open => 'opened',
          PullState.merged => 'merged',
          _ => null, // drafts wait for "ready for review"; closed-at-birth is noise
        };
      }
    } else if (prev.state != PullState.merged && p.state == PullState.merged) {
      verb = 'merged';
    } else if (prev.state == PullState.closed && (p.state == PullState.open || p.state == PullState.draft)) {
      verb = 'reopened';
    } else if (prev.draft && p.state == PullState.open) {
      verb = 'ready for review';
    }
    // Merges are worth knowing about even for your own PRs; the rest isn't.
    if (verb == null || isBotLogin(author) || (isSelf && verb != 'merged')) continue;
    out.add(
      GitEvent(
        title: '${repo.name} · PR #${p.number} $verb',
        body: _truncate('$author: ${p.title}'),
        route: Routes.pull(repo, p.number),
        tag: 'pr-${repo.fullName}-${p.number}-$verb',
      ),
    );
  }
  return out;
}

/// Event for new commits on a branch. [commits] are oldest-first, already
/// filtered (no self/bot commits). Returns null when there's nothing to say.
GitEvent? pushEvent(
  RepoRef repo, {
  required String branch,
  required String? from,
  required String to,
  required List<GhCommit> commits,
  bool forced = false,
}) {
  if (commits.isEmpty) return null;
  final label = '${repo.name} · $branch';
  final head = commits.last;
  if (commits.length == 1 && !forced) {
    return GitEvent(
      title: label,
      body: _truncate('${head.authorLogin ?? head.authorName}: ${head.title}'),
      route: Routes.commit(repo, head.sha),
      tag: 'push-${repo.fullName}-$branch-$to',
    );
  }
  final listed = commits.reversed.take(3).map((c) => '• ${_truncate(c.title, 60)}').join('\n');
  final more = commits.length > 3 ? '\n+${commits.length - 3} more' : '';
  return GitEvent(
    title: forced ? '$label force-pushed' : '$label: ${commits.length} new commits',
    body: listed + more,
    route: from == null || forced ? Routes.commit(repo, to) : Routes.compare(repo, from, to),
    tag: 'push-${repo.fullName}-$branch-$to',
  );
}

String _truncate(String s, [int max = 120]) => s.length > max ? '${s.substring(0, max - 1)}…' : s;

import '../../data/github/models/models.dart';

/// Counts of a commit's checks by outcome.
class ChecksSummary {
  const ChecksSummary({this.passed = 0, this.failed = const [], this.running = 0, this.skipped = 0});

  factory ChecksSummary.of(List<GhCheckRun> checks) {
    var passed = 0, running = 0, skipped = 0;
    final failed = <String>[];
    for (final c in checks) {
      switch (c.state) {
        case RunState.success:
          passed++;
        case RunState.failure || RunState.actionRequired:
          failed.add(c.name);
        case RunState.queued || RunState.waiting || RunState.inProgress:
          running++;
        case RunState.cancelled || RunState.skipped || RunState.neutral:
          skipped++;
      }
    }
    return ChecksSummary(passed: passed, failed: failed, running: running, skipped: skipped);
  }

  final int passed;

  /// Names of the failing checks.
  final List<String> failed;
  final int running;

  /// Skipped, neutral or cancelled: neither pass nor fail.
  final int skipped;

  int get total => passed + failed.length + running + skipped;

  /// "1 failing (test)", "2 running", "3 passed, 1 skipped", "No checks".
  String get label {
    if (total == 0) return 'No checks';
    final parts = [
      if (failed.isNotEmpty) '${failed.length} failing (${failed.take(2).join(', ')}${failed.length > 2 ? '…' : ''})',
      if (running > 0) '$running running',
      if (passed > 0) '$passed passed',
      if (skipped > 0) '$skipped skipped',
    ];
    return parts.join(', ');
  }
}

enum Verdict {
  /// Merged or closed: nothing to decide.
  done,

  /// Something must change first: conflicts, failing checks, changes requested.
  blocked,

  /// Not yet: draft, checks running, required reviews missing, still computing.
  waiting,
  ready,
}

/// Answers "is this safe to merge?" from what GitHub reports: the merge state,
/// the head commit's checks and the reviewers' latest verdicts. Pure, so it's
/// tested without widgets.
class MergeReadiness {
  const MergeReadiness({
    required this.verdict,
    required this.headline,
    this.checks,
    this.merge,
    this.approvedBy = const [],
    this.changesRequestedBy = const [],
  });

  /// [checks] and [reviewers] are null while loading or when unavailable;
  /// [checksUnavailable] says the checks couldn't be loaded (offline, say).
  /// The verdict never claims what it can't see.
  factory MergeReadiness.of(
    GhPull pull, {
    List<GhCheckRun>? checks,
    Map<String, ReviewState>? reviewers,
    bool checksUnavailable = false,
  }) {
    final summary = checks == null ? null : ChecksSummary.of(checks);
    final approved = [
      for (final e in (reviewers ?? const {}).entries)
        if (e.value == ReviewState.approved) e.key,
    ];
    final changes = [
      for (final e in (reviewers ?? const {}).entries)
        if (e.value == ReviewState.changesRequested) e.key,
    ];
    final merge = switch (pull.mergeableState) {
      'dirty' => 'Conflicts with ${pull.baseRef}',
      'behind' => 'Behind ${pull.baseRef}',
      'clean' || 'unstable' || 'has_hooks' || 'blocked' => 'No conflicts with ${pull.baseRef}',
      _ => null,
    };
    (Verdict, String) decide() {
      if (pull.state == PullState.merged) return (Verdict.done, 'Merged');
      if (pull.state == PullState.closed) return (Verdict.done, 'Closed');
      if (pull.mergeableState == 'dirty') return (Verdict.blocked, 'Has conflicts');
      if (summary != null && summary.failed.isNotEmpty) return (Verdict.blocked, 'Checks failing');
      if (changes.isNotEmpty) return (Verdict.blocked, 'Changes requested');
      if (pull.state == PullState.draft) return (Verdict.waiting, 'Draft');
      if (summary != null && summary.running > 0) return (Verdict.waiting, 'Checks running');
      if (pull.mergeableState == 'blocked') {
        return (Verdict.waiting, approved.isEmpty ? 'Needs approval' : 'Waiting for required checks or reviews');
      }
      if (summary == null && checksUnavailable) return (Verdict.waiting, 'Checks unavailable');
      if (summary == null || merge == null) return (Verdict.waiting, 'Checking…');
      return (Verdict.ready, 'Ready to merge');
    }

    final (verdict, headline) = decide();
    return MergeReadiness(
      verdict: verdict,
      headline: headline,
      checks: summary,
      merge: merge,
      approvedBy: approved,
      changesRequestedBy: changes,
    );
  }

  final Verdict verdict;
  final String headline;
  final ChecksSummary? checks;

  /// "No conflicts with main", "Conflicts with main", "Behind main"; null when unknown.
  final String? merge;
  final List<String> approvedBy;
  final List<String> changesRequestedBy;

  /// "Changes requested by marco-rossi", "Approved by lena-k", "No approvals yet".
  String get reviews => changesRequestedBy.isNotEmpty
      ? 'Changes requested by ${changesRequestedBy.join(', ')}'
      : approvedBy.isNotEmpty
      ? 'Approved by ${approvedBy.join(', ')}'
      : 'No approvals yet';

  /// The header's one line: the headline and the most useful detail.
  String get summary => switch (headline) {
    'Checks failing' || 'Checks running' => '$headline · ${checks!.label}',
    'Has conflicts' || 'Merged' || 'Closed' => headline,
    'Changes requested' => '$headline · ${changesRequestedBy.join(', ')}',
    _ when checks != null && checks!.total > 0 => '$headline · ${checks!.label}',
    _ => headline,
  };
}

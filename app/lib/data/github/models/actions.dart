import 'repo.dart';

/// Where a workflow run, job or step is, from GitHub's `status` and
/// `conclusion` (the conclusion is only set once it's completed).
enum RunState {
  queued,
  waiting,
  inProgress,
  success,
  failure,
  cancelled,
  skipped,
  neutral,
  actionRequired;

  static RunState from(String? status, String? conclusion) => switch (status) {
    'completed' => switch (conclusion) {
      'success' => success,
      'failure' || 'timed_out' || 'startup_failure' => failure,
      'cancelled' => cancelled,
      'skipped' => skipped,
      'action_required' => actionRequired,
      _ => neutral, // neutral, stale
    },
    'in_progress' => inProgress,
    'waiting' || 'pending' => waiting,
    _ => queued, // queued, requested
  };

  /// Still going: worth refreshing, and can be cancelled.
  bool get isActive => this == queued || this == waiting || this == inProgress;

  String get label => switch (this) {
    queued => 'Queued',
    waiting => 'Waiting',
    inProgress => 'In progress',
    success => 'Succeeded',
    failure => 'Failed',
    cancelled => 'Cancelled',
    skipped => 'Skipped',
    neutral => 'Completed',
    actionRequired => 'Action required',
  };
}

class GhWorkflow {
  const GhWorkflow({required this.id, required this.name, required this.path, required this.state});

  factory GhWorkflow.fromJson(Map<String, dynamic> j) => GhWorkflow(
    id: j['id'] as int,
    name: (j['name'] as String?) ?? '',
    path: (j['path'] as String?) ?? '',
    state: (j['state'] as String?) ?? 'active',
  );

  final int id;
  final String name;

  /// `.github/workflows/ci.yml`; GitHub's own workflows (Pages, Dependabot)
  /// have a `dynamic/…` path and no file.
  final String path;

  /// `active`, `disabled_manually`, `disabled_inactivity`…
  final String state;

  bool get isActive => state == 'active';

  /// Lives in the repo, so its file says how it can be started.
  bool get hasFile => path.startsWith('.github/workflows/');
}

class GhWorkflowRun {
  const GhWorkflowRun({
    required this.id,
    required this.title,
    required this.workflowName,
    required this.workflowId,
    required this.runNumber,
    required this.attempt,
    required this.event,
    required this.state,
    required this.headSha,
    this.headBranch,
    this.actor,
    required this.createdAt,
    required this.updatedAt,
    this.startedAt,
    this.htmlUrl,
  });

  factory GhWorkflowRun.fromJson(Map<String, dynamic> j) {
    final actor = (j['triggering_actor'] ?? j['actor']) as Map<String, dynamic>?;
    final created = DateTime.parse(j['created_at'] as String);
    return GhWorkflowRun(
      id: j['id'] as int,
      title: (j['display_title'] as String?) ?? (j['name'] as String?) ?? '',
      workflowName: (j['name'] as String?) ?? '',
      workflowId: j['workflow_id'] as int,
      runNumber: (j['run_number'] as int?) ?? 0,
      attempt: (j['run_attempt'] as int?) ?? 1,
      event: (j['event'] as String?) ?? '',
      state: RunState.from(j['status'] as String?, j['conclusion'] as String?),
      headSha: (j['head_sha'] as String?) ?? '',
      headBranch: j['head_branch'] as String?,
      actor: actor == null ? null : GhUser.fromJson(actor),
      createdAt: created,
      updatedAt: DateTime.tryParse((j['updated_at'] as String?) ?? '') ?? created,
      startedAt: DateTime.tryParse((j['run_started_at'] as String?) ?? ''),
      htmlUrl: j['html_url'] as String?,
    );
  }

  final int id;

  /// The commit message, PR title or the workflow's `run-name`.
  final String title;
  final String workflowName;
  final int workflowId;
  final int runNumber;
  final int attempt;

  /// What started it: `push`, `pull_request`, `workflow_dispatch`, `schedule`…
  final String event;
  final RunState state;
  final String headSha;
  final String? headBranch;
  final GhUser? actor;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? startedAt;
  final String? htmlUrl;

  /// How long it ran (so far, while active).
  Duration duration({DateTime? now}) {
    final end = state.isActive ? (now ?? DateTime.now()) : updatedAt;
    final d = end.difference(startedAt ?? createdAt);
    return d.isNegative ? Duration.zero : d;
  }
}

class GhJob {
  const GhJob({
    required this.id,
    required this.name,
    required this.state,
    this.startedAt,
    this.completedAt,
    this.steps = const [],
    this.htmlUrl,
  });

  factory GhJob.fromJson(Map<String, dynamic> j) => GhJob(
    id: j['id'] as int,
    name: (j['name'] as String?) ?? '',
    state: RunState.from(j['status'] as String?, j['conclusion'] as String?),
    startedAt: DateTime.tryParse((j['started_at'] as String?) ?? ''),
    completedAt: DateTime.tryParse((j['completed_at'] as String?) ?? ''),
    steps: [for (final s in (j['steps'] as List<dynamic>?) ?? const []) GhJobStep.fromJson(s as Map<String, dynamic>)],
    htmlUrl: j['html_url'] as String?,
  );

  final int id;
  final String name;
  final RunState state;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final List<GhJobStep> steps;
  final String? htmlUrl;

  /// Null until it starts.
  Duration? duration({DateTime? now}) {
    final start = startedAt;
    if (start == null) return null;
    final d = (completedAt ?? now ?? DateTime.now()).difference(start);
    return d.isNegative ? Duration.zero : d;
  }
}

class GhJobStep {
  const GhJobStep({required this.number, required this.name, required this.state});

  factory GhJobStep.fromJson(Map<String, dynamic> j) => GhJobStep(
    number: (j['number'] as int?) ?? 0,
    name: (j['name'] as String?) ?? '',
    state: RunState.from(j['status'] as String?, j['conclusion'] as String?),
  );

  final int number;
  final String name;
  final RunState state;
}

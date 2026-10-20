import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/routing/routes.dart';
import '../../core/utils/relative_time.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/common.dart';
import '../../data/github/github_exception.dart';
import '../../data/github/models/models.dart';
import '../auth/auth_controller.dart';
import '../offline/offline_providers.dart';
import 'actions_providers.dart';
import 'run_widgets.dart';

class RunScreen extends StatelessWidget {
  const RunScreen({super.key, required this.repo, required this.runId});

  final RepoRef repo;
  final int runId;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('${repo.name} · run')),
    body: RunView(repo: repo, runId: runId),
  );
}

/// What went wrong with a write to Actions, with the usual fix for 403.
String actionError(Object e) {
  if (e is! GitHubException) return '$e';
  if (e.statusCode == 403 && !e.isRateLimited) {
    return '${e.message}. This needs write access to the repo; a fine-grained token also needs the '
        '"Actions" permission set to "Read and write".';
  }
  return e.message;
}

/// A run's summary, its jobs and their steps, with Re-run and Cancel.
/// Refreshes itself while the run is going. Embeddable in split view.
class RunView extends ConsumerStatefulWidget {
  const RunView({super.key, required this.repo, required this.runId});

  final RepoRef repo;
  final int runId;

  @override
  ConsumerState<RunView> createState() => _RunViewState();
}

class _RunViewState extends ConsumerState<RunView> {
  var _busy = false;

  /// A re-run or cancel takes a moment to show in the run's status, so it
  /// keeps refreshing until then.
  DateTime? _expectChangeUntil;

  RunKey get _key => (repo: widget.repo, id: widget.runId);

  void _refresh() {
    ref.invalidate(runProvider(_key));
    ref.invalidate(runJobsProvider(_key));
  }

  Future<void> _act(String done, Future<void> Function() call) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await call();
      messenger.showSnackBar(SnackBar(content: Text(done)));
      _expectChangeUntil = DateTime.now().add(const Duration(seconds: 30));
      _refresh();
      ref.invalidate(runListProvider);
    } on Object catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(actionError(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancel() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel this run?'),
        content: const Text('Jobs that are running stop, and the run ends as cancelled.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep running')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Cancel run')),
        ],
      ),
    );
    if (ok != true) return;
    final api = ref.read(githubApiProvider);
    await _act('Cancelling the run', () => api.cancelWorkflowRun(widget.repo, widget.runId));
  }

  @override
  Widget build(BuildContext context) {
    final run = ref.watch(runProvider(_key));
    final jobs = ref.watch(runJobsProvider(_key));
    final canAct = ref.watch(isSignedInProvider) && !ref.watch(isOfflineProvider(widget.repo));
    final api = ref.read(githubApiProvider);
    final active = (run.value?.state.isActive ?? false) || (_expectChangeUntil?.isAfter(DateTime.now()) ?? false);
    return AutoRefresh(
      // Signed out, GitHub allows 60 requests an hour: refresh by hand.
      active: ref.watch(isSignedInProvider) && active,
      every: const Duration(seconds: 10),
      onRefresh: _refresh,
      child: AsyncView(
        // A failed refresh keeps showing what was loaded; the next one retries.
        value: run.hasValue ? AsyncData(run.requireValue) : run,
        onRetry: _refresh,
        data: (r) => RefreshIndicator(
          onRefresh: () async {
            _refresh();
            await ref.read(runProvider(_key).future);
          },
          child: ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              _RunHeader(run: r, repo: widget.repo),
              if (canAct || r.htmlUrl != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (canAct && r.state.isActive)
                        OutlinedButton.icon(
                          icon: const Icon(Icons.stop_circle_outlined),
                          label: const Text('Cancel run'),
                          onPressed: _busy ? null : _cancel,
                        ),
                      if (canAct && r.state == RunState.failure)
                        FilledButton.tonalIcon(
                          icon: const Icon(Icons.replay),
                          label: const Text('Re-run failed jobs'),
                          onPressed: _busy
                              ? null
                              : () => _act('Re-running failed jobs', () => api.rerunFailedJobs(widget.repo, r.id)),
                        ),
                      if (canAct && !r.state.isActive)
                        OutlinedButton.icon(
                          icon: const Icon(Icons.replay),
                          label: const Text('Re-run all jobs'),
                          onPressed: _busy
                              ? null
                              : () => _act('Re-running all jobs', () => api.rerunWorkflowRun(widget.repo, r.id)),
                        ),
                      if (r.htmlUrl case final url?)
                        TextButton.icon(
                          icon: const Icon(Icons.open_in_new),
                          label: const Text('Open on GitHub'),
                          onPressed: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
                        ),
                    ],
                  ),
                ),
              const Divider(height: 1),
              const SectionHeader('Jobs'),
              switch (jobs) {
                AsyncValue(hasValue: true, :final requireValue) when requireValue.isEmpty => const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No jobs yet.'),
                ),
                AsyncValue(hasValue: true, :final requireValue) => Column(
                  children: [for (final j in requireValue) _JobTile(key: ValueKey(j.id), job: j, repo: widget.repo)],
                ),
                AsyncError(:final error) => ErrorView(
                  error: error,
                  onRetry: () => ref.invalidate(runJobsProvider(_key)),
                ),
                _ => const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                ),
              },
            ],
          ),
        ),
      ),
    );
  }
}

class _RunHeader extends StatelessWidget {
  const _RunHeader({required this.run, required this.repo});

  final GhWorkflowRun run;
  final RepoRef repo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final small = theme.textTheme.bodySmall;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RunStateIcon(run.state, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(run.title, style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  '${run.workflowName} #${run.runNumber}'
                  '${run.attempt > 1 ? ' · attempt ${run.attempt}' : ''} · ${run.state.label}',
                  style: small,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (run.headBranch case final b?)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.call_split, size: 16),
                          const SizedBox(width: 2),
                          Flexible(
                            child: Text(b, style: small, overflow: TextOverflow.ellipsis),
                          ),
                        ],
                      ),
                    if (run.headSha.isNotEmpty)
                      InkWell(onTap: () => context.push(Routes.commit(repo, run.headSha)), child: ShaChip(run.headSha)),
                    Text(eventLabel(run.event), style: small),
                    if (run.actor case final a?)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          UserAvatar(url: a.avatarUrl, fallback: a.login, size: 18),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(a.login, style: small, overflow: TextOverflow.ellipsis),
                          ),
                        ],
                      ),
                    Text('${relativeTime(run.createdAt)} · ${shortDuration(run.duration())}', style: small),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _JobTile extends StatelessWidget {
  const _JobTile({super.key, required this.job, required this.repo});

  final GhJob job;
  final RepoRef repo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // A skipped job never ran: GitHub gives it a zero duration.
    final duration = job.state == RunState.skipped ? null : job.duration();
    return ExpansionTile(
      // Failures are what you came for.
      initiallyExpanded: job.state == RunState.failure,
      leading: RunStateIcon(job.state),
      title: Text(job.name),
      subtitle: Text(
        duration == null ? job.state.label : '${job.state.label} · ${shortDuration(duration)}',
        style: theme.textTheme.bodySmall,
      ),
      children: [
        for (final s in job.steps)
          ListTile(
            dense: true,
            contentPadding: const EdgeInsetsDirectional.only(start: 32, end: 16),
            leading: RunStateIcon(s.state, size: 18),
            title: Text(s.name),
          ),
        ListTile(
          dense: true,
          contentPadding: const EdgeInsetsDirectional.only(start: 32, end: 16),
          leading: const Icon(Icons.article_outlined, size: 18),
          title: const Text('View log'),
          onTap: () => context.push(Routes.jobLog(repo, job.id)),
        ),
      ],
    );
  }
}

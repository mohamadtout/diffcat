import 'dart:isolate';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/github/models/models.dart';
import '../auth/auth_controller.dart';
import '../repo/repo_providers.dart';
import 'job_log.dart';
import 'workflow_dispatch.dart';

final workflowsProvider = FutureProvider.autoDispose.family<List<GhWorkflow>, RepoRef>(
  (ref, r) => ref.watch(githubApiProvider).workflows(r),
);

/// [workflowId] null: runs of every workflow.
typedef RunListKey = ({RepoRef repo, int? workflowId});

final runListProvider = AsyncNotifierProvider.autoDispose.family<RunListNotifier, Paged<GhWorkflowRun>, RunListKey>(
  RunListNotifier.new,
);

class RunListNotifier extends AsyncNotifier<Paged<GhWorkflowRun>> {
  RunListNotifier(this.key);
  final RunListKey key;

  @override
  Future<Paged<GhWorkflowRun>> build() async {
    final page = await ref.watch(githubApiProvider).workflowRuns(key.repo, workflowId: key.workflowId);
    return Paged(page.items, hasMore: page.hasNext);
  }

  /// Reloads the newest page in place, keeping the older pages already
  /// loaded (a plain refresh would drop them and jump the list to the top).
  /// For polling: failures are ignored, the next tick tries again.
  Future<void> refreshNewest() async {
    final current = state.value;
    if (current == null || current.loadingMore) return;
    try {
      final first = await ref.read(githubApiProvider).workflowRuns(key.repo, workflowId: key.workflowId);
      // Re-read: a page may have loaded meanwhile.
      final now = ref.mounted ? state.value : null;
      if (now == null || now.loadingMore) return;
      final ids = {for (final r in first.items) r.id};
      state = AsyncData(
        now.copyWith(
          items: [...first.items, ...now.items.where((r) => !ids.contains(r.id))],
          hasMore: now.page == 1 ? first.hasNext : now.hasMore,
          loadMoreError: now.loadMoreError,
        ),
      );
    } on Object {
      // Shown on the next manual refresh, if it persists.
    }
  }

  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || !current.hasMore || current.loadingMore || current.loadMoreError != null) return;
    state = AsyncData(current.copyWith(loadingMore: true));
    try {
      final next = await ref
          .read(githubApiProvider)
          .workflowRuns(key.repo, workflowId: key.workflowId, page: current.page + 1);
      if (!ref.mounted) return;
      // New runs push older ones onto later pages, so a page can repeat some.
      final ids = {for (final r in current.items) r.id};
      state = AsyncData(
        Paged(
          [...current.items, ...next.items.where((r) => !ids.contains(r.id))],
          hasMore: next.hasNext,
          page: current.page + 1,
        ),
      );
    } catch (e) {
      // Called fire-and-forget from scrolling: never throw, surface it instead.
      if (!ref.mounted) return;
      state = AsyncData(current.copyWith(loadingMore: false, loadMoreError: e));
    }
  }

  /// Clears a failed page so scrolling can try again.
  void retryLoadMore() {
    final current = state.value;
    if (current == null) return;
    state = AsyncData(current.copyWith());
    loadMore();
  }
}

typedef RunKey = ({RepoRef repo, int id});

final runProvider = FutureProvider.autoDispose.family<GhWorkflowRun, RunKey>(
  (ref, k) => ref.watch(githubApiProvider).workflowRun(k.repo, k.id),
);

final runJobsProvider = FutureProvider.autoDispose.family<List<GhJob>, RunKey>(
  (ref, k) => ref.watch(githubApiProvider).runJobs(k.repo, k.id),
);

typedef JobKey = ({RepoRef repo, int id});

final jobProvider = FutureProvider.autoDispose.family<GhJob, JobKey>(
  (ref, k) => ref.watch(githubApiProvider).job(k.repo, k.id),
);

/// A job's log, parsed (on a background isolate when it's long).
final jobLogProvider = FutureProvider.autoDispose.family<List<LogLine>, JobKey>((ref, k) async {
  final raw = await ref.watch(githubApiProvider).jobLog(k.repo, k.id);
  return raw.length < 200000 ? parseJobLog(raw) : Isolate.run(() => parseJobLog(raw));
});

typedef DispatchKey = ({RepoRef repo, String path, String ref});

/// How the workflow file at [DispatchKey.path] can be started by hand on
/// [DispatchKey.ref]: null when it has no `workflow_dispatch` trigger there.
final workflowDispatchProvider = FutureProvider.autoDispose.family<WorkflowDispatch?, DispatchKey>((ref, k) async {
  final source = await ref.watch(githubApiProvider).fileContent(k.repo, k.path, k.ref);
  return parseWorkflowDispatch(source);
});

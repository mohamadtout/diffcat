import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/layout/split_view.dart';
import '../../core/routing/routes.dart';
import '../../core/widgets/async_view.dart';
import '../../data/github/models/models.dart';
import '../auth/auth_controller.dart';
import '../offline/offline_providers.dart';
import '../repo/repo_providers.dart';
import 'actions_providers.dart';
import 'run_screen.dart';
import 'run_widgets.dart';
import 'run_workflow_sheet.dart';

/// Workflow runs (GitHub Actions), filtered by workflow, and Run workflow.
class ActionsTab extends ConsumerStatefulWidget {
  const ActionsTab({super.key, required this.repo, required this.gitRef});

  final RepoRef repo;

  /// The branch picked on the repo screen: where Run workflow starts.
  final String gitRef;

  @override
  ConsumerState<ActionsTab> createState() => _ActionsTabState();
}

class _ActionsTabState extends ConsumerState<ActionsTab> {
  int? _workflowId;
  int? _selected;

  /// After starting a workflow GitHub takes a few seconds to list its run,
  /// so the list keeps checking until then.
  DateTime? _expectRunUntil;

  RunListKey get _key => (repo: widget.repo, workflowId: _workflowId);

  Future<void> _runWorkflow(List<GhWorkflow> workflows) async {
    final started = await showRunWorkflowSheet(
      context,
      repo: widget.repo,
      gitRef: widget.gitRef,
      workflows: workflows,
      initialWorkflowId: _workflowId,
    );
    if (started == null || !mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Started ${started.name}. Its run appears here in a few seconds.')));
    setState(() => _expectRunUntil = DateTime.now().add(const Duration(minutes: 1)));
    await Future<void>.delayed(const Duration(seconds: 3));
    if (mounted) await ref.read(runListProvider(_key).notifier).refreshNewest();
  }

  @override
  Widget build(BuildContext context) {
    final split = SplitView.isActive(context);
    final workflows = ref.watch(workflowsProvider(widget.repo));
    final canRun = ref.watch(isSignedInProvider) && !ref.watch(isOfflineProvider(widget.repo));
    final list = ref.watch(runListProvider(_key));
    final runs = list.value?.items ?? const <GhWorkflowRun>[];
    final expecting = _expectRunUntil?.isAfter(DateTime.now()) ?? false;
    return SplitView(
      placeholder: 'Select a workflow run',
      master: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
            child: Row(
              children: [
                Expanded(
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: _WorkflowFilter(
                      workflows: workflows.value ?? const [],
                      selected: _workflowId,
                      onSelected: (id) => setState(() {
                        _workflowId = id;
                        _selected = null;
                      }),
                    ),
                  ),
                ),
                if (canRun && workflows.hasValue && workflows.value!.any((w) => w.hasFile && w.isActive)) ...[
                  const SizedBox(width: 8),
                  FilledButton.tonalIcon(
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Run workflow'),
                    onPressed: () => _runWorkflow(workflows.value!),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: AutoRefresh(
              // Signed out, GitHub allows 60 requests an hour: refresh by hand.
              active: ref.watch(isSignedInProvider) && (expecting || runs.any((r) => r.state.isActive)),
              onRefresh: () => ref.read(runListProvider(_key).notifier).refreshNewest(),
              child: AsyncView(
                value: list,
                onRetry: () => ref.invalidate(runListProvider(_key)),
                data: (paged) => paged.items.isEmpty
                    ? RefreshIndicator(
                        onRefresh: () => ref.refresh(runListProvider(_key).future),
                        child: LayoutBuilder(
                          builder: (context, c) => SingleChildScrollView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            child: SizedBox(
                              height: c.maxHeight,
                              child: EmptyView(
                                icon: Icons.play_circle_outline,
                                message: workflows.value?.isEmpty ?? false
                                    ? 'This repo has no GitHub Actions workflows.'
                                    : 'No workflow runs.',
                              ),
                            ),
                          ),
                        ),
                      )
                    : _RunList(
                        listKey: _key,
                        paged: paged,
                        selected: split ? _selected : null,
                        onTap: (r) =>
                            split ? setState(() => _selected = r.id) : context.push(Routes.run(widget.repo, r.id)),
                      ),
              ),
            ),
          ),
        ],
      ),
      detail: _selected == null ? null : RunView(key: ValueKey(_selected), repo: widget.repo, runId: _selected!),
    );
  }
}

class _WorkflowFilter extends StatelessWidget {
  const _WorkflowFilter({required this.workflows, required this.selected, required this.onSelected});

  final List<GhWorkflow> workflows;
  final int? selected;
  final ValueChanged<int?> onSelected;

  @override
  Widget build(BuildContext context) {
    final current = workflows.where((w) => w.id == selected).firstOrNull;
    final sorted = [...workflows]
      ..sort(
        (a, b) => a.isActive == b.isActive
            ? a.name.toLowerCase().compareTo(b.name.toLowerCase())
            : a.isActive
            ? -1
            : 1,
      );
    // 0 stands for "all": a popup item's null value would count as cancelled.
    return PopupMenuButton<int>(
      tooltip: 'Filter by workflow',
      initialValue: selected ?? 0,
      onSelected: (id) => onSelected(id == 0 ? null : id),
      itemBuilder: (_) => [
        const PopupMenuItem(value: 0, child: Text('All workflows')),
        for (final w in sorted) PopupMenuItem(value: w.id, child: Text(w.isActive ? w.name : '${w.name} (disabled)')),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.filter_list, size: 20),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                current?.name ?? 'All workflows',
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            const Icon(Icons.arrow_drop_down),
          ],
        ),
      ),
    );
  }
}

class _RunList extends ConsumerWidget {
  const _RunList({required this.listKey, required this.paged, required this.onTap, this.selected});

  final RunListKey listKey;
  final Paged<GhWorkflowRun> paged;
  final ValueChanged<GhWorkflowRun> onTap;
  final int? selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(runListProvider(listKey).notifier);
    return RefreshIndicator(
      onRefresh: () => ref.refresh(runListProvider(listKey).future),
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n.metrics.extentAfter < 600) notifier.loadMore();
          return false;
        },
        child: ListView.builder(
          itemCount: paged.items.length + 1,
          itemBuilder: (context, i) {
            if (i == paged.items.length) {
              if (paged.loadMoreError != null) {
                return ListTile(
                  leading: const Icon(Icons.error_outline),
                  title: const Text("Couldn't load more runs"),
                  trailing: TextButton(onPressed: notifier.retryLoadMore, child: const Text('Retry')),
                );
              }
              return paged.hasMore
                  ? const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : const SizedBox(height: 32);
            }
            final r = paged.items[i];
            return RunTile(run: r, selected: r.id == selected, onTap: () => onTap(r));
          },
        ),
      ),
    );
  }
}

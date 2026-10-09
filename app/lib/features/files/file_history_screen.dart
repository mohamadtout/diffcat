import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/layout/split_view.dart';
import '../../core/routing/routes.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/async_view.dart';
import '../../data/github/models/models.dart';
import '../commits/commit_screen.dart';
import '../repo/repo_providers.dart';
import 'file_history_providers.dart';
import 'history_graph.dart';
import 'history_graph_view.dart';

/// Every commit that touched [path], drawn as a graph across branches: where
/// a branch forked, its own commits, rebased or cherry-picked copies and
/// reverts. Tapping a commit opens it scrolled to (and highlighting) this
/// file's diff; compare mode diffs any two versions of the file.
class FileHistoryScreen extends ConsumerStatefulWidget {
  const FileHistoryScreen({super.key, required this.repo, required this.path, required this.gitRef});

  final RepoRef repo;
  final String path;
  final String gitRef;

  @override
  ConsumerState<FileHistoryScreen> createState() => _FileHistoryScreenState();
}

class _FileHistoryScreenState extends ConsumerState<FileHistoryScreen> {
  String? _selected;
  bool _comparing = false;

  /// Versions picked in compare mode, oldest pick first.
  final _picked = <String>[];

  FileHistoryKey get _key => (repo: widget.repo, path: widget.path, ref: widget.gitRef);

  void _tap(GraphRow row) {
    final sha = row.node.sha;
    if (_comparing) {
      setState(() {
        if (!_picked.remove(sha)) {
          _picked.add(sha);
          if (_picked.length > 2) _picked.removeAt(0);
        }
      });
    } else if (SplitView.isActive(context)) {
      setState(() => _selected = sha);
    } else {
      context.push(Routes.commit(widget.repo, sha, file: widget.path));
    }
  }

  void _compare(HistoryGraph graph) {
    // Rows are newest first: the lower row is the older version.
    final rows = [for (final sha in _picked) graph.rowOf(sha) ?? 0]..sort();
    context.push(
      Routes.compare(widget.repo, graph.rows[rows[1]].node.sha, graph.rows[rows[0]].node.sha, file: widget.path),
    );
  }

  Future<void> _pickBranches(FileHistory history) async {
    final picked = await showModalBottomSheet<List<String>>(
      context: context,
      useRootNavigator: true, // cover the shell navigation bar/rail
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => BranchPickerSheet(repo: widget.repo, base: history.logs.first.name, initial: history.branches),
    );
    if (picked != null) await ref.read(fileHistoryProvider(_key).notifier).setBranches(picked);
  }

  void _actions(GhCommit c) => showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    showDragHandle: true,
    builder: (sheet) {
      void go(String route) {
        Navigator.pop(sheet);
        context.push(route);
      }

      return SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              title: Text(c.title, maxLines: 2, overflow: TextOverflow.ellipsis),
              subtitle: Text(c.shortSha, style: TextStyle(fontFamily: AppTheme.monoFamily)),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.commit),
              title: const Text('Open commit'),
              onTap: () => go(Routes.commit(widget.repo, c.sha, file: widget.path)),
            ),
            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: const Text('View file at this version'),
              onTap: () => go(Routes.file(widget.repo, widget.path, c.sha)),
            ),
            ListTile(
              leading: const Icon(Icons.compare_arrows),
              title: Text('Compare with ${widget.gitRef}'),
              onTap: () => go(Routes.compare(widget.repo, c.sha, widget.gitRef, file: widget.path)),
            ),
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text('Copy SHA'),
              onTap: () {
                Clipboard.setData(ClipboardData(text: c.sha));
                Navigator.pop(sheet);
              },
            ),
          ],
        ),
      );
    },
  );

  @override
  Widget build(BuildContext context) {
    final provider = fileHistoryProvider(_key);
    final value = ref.watch(provider);
    final history = value.value;
    final split = SplitView.isActive(context);
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('File history'),
            Text(widget.path, style: Theme.of(context).textTheme.labelSmall, overflow: TextOverflow.ellipsis),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Branches',
            icon: const Icon(Icons.account_tree_outlined),
            onPressed: history == null || history.busy ? null : () => _pickBranches(history),
          ),
          IconButton(
            tooltip: 'Compare two versions',
            isSelected: _comparing,
            icon: const Icon(Icons.compare_arrows),
            onPressed: () => setState(() {
              _comparing = !_comparing;
              _picked.clear();
            }),
          ),
        ],
      ),
      body: SplitView(
        placeholder: 'Select a commit',
        master: AsyncView(
          value: value,
          onRetry: () => ref.invalidate(provider),
          data: (h) => _HistoryList(
            history: h,
            selected: split ? _selected : null,
            picked: _comparing ? _picked : const [],
            onTap: _tap,
            onLongPress: (r) => _actions(r.node.commit),
            onAddBranches: h.busy ? null : () => _pickBranches(h),
            onRefresh: () => ref.refresh(provider.future),
            onLoadMore: ref.read(provider.notifier).loadMore,
            onRetryLoadMore: ref.read(provider.notifier).retryLoadMore,
          ),
        ),
        detail: _selected == null
            ? null
            : CommitView(key: ValueKey(_selected), repo: widget.repo, sha: _selected!, focusPath: widget.path),
      ),
      bottomNavigationBar: !_comparing || history == null
          ? null
          : _CompareBar(picked: _picked, onCompare: _picked.length == 2 ? () => _compare(history.graph) : null),
    );
  }
}

class _HistoryList extends StatelessWidget {
  const _HistoryList({
    required this.history,
    required this.selected,
    required this.picked,
    required this.onTap,
    required this.onLongPress,
    required this.onAddBranches,
    required this.onRefresh,
    required this.onLoadMore,
    required this.onRetryLoadMore,
  });

  final FileHistory history;
  final String? selected;
  final List<String> picked;
  final ValueChanged<GraphRow> onTap;
  final ValueChanged<GraphRow> onLongPress;
  final VoidCallback? onAddBranches;
  final Future<void> Function() onRefresh;
  final VoidCallback onLoadMore;
  final VoidCallback onRetryLoadMore;

  @override
  Widget build(BuildContext context) {
    final graph = history.graph;
    final theme = Theme.of(context);
    if (graph.rows.isEmpty) {
      return const EmptyView(icon: Icons.history, message: 'No commits touch this file on this branch.');
    }
    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GraphLegend(graph: graph, errors: {for (final l in history.logs) l.name: ?l.error}, onAdd: onAddBranches),
        if (history.busy) const LinearProgressIndicator(minHeight: 2) else const SizedBox(height: 2),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: Text(
            'Renames are not followed: history before a rename appears under the old path.',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
          ),
        ),
      ],
    );

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n.metrics.extentAfter < 600) onLoadMore();
          return false;
        },
        child: ListView.builder(
          itemCount: graph.rows.length + 2,
          itemBuilder: (context, i) {
            if (i == 0) return header;
            if (i == graph.rows.length + 1) {
              if (history.loadMoreError != null) {
                return ListTile(
                  leading: const Icon(Icons.error_outline),
                  title: const Text("Couldn't load older commits"),
                  trailing: TextButton(onPressed: onRetryLoadMore, child: const Text('Retry')),
                );
              }
              return history.hasMore
                  ? const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : const SizedBox(height: 32);
            }
            final row = graph.rows[i - 1];
            return GraphRowTile(
              row: row,
              graph: graph,
              selected: row.node.sha == selected,
              picked: picked.contains(row.node.sha),
              onTap: () => onTap(row),
              onLongPress: () => onLongPress(row),
            );
          },
        ),
      ),
    );
  }
}

class _CompareBar extends StatelessWidget {
  const _CompareBar({required this.picked, required this.onCompare});

  final List<String> picked;
  final VoidCallback? onCompare;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = switch (picked.length) {
      0 => 'Tap two versions to compare',
      1 => '${picked[0].substring(0, 7)} and one more',
      _ => '${picked[0].substring(0, 7)} ↔ ${picked[1].substring(0, 7)}',
    };
    return Material(
      color: theme.colorScheme.surfaceContainer,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
          child: Row(
            children: [
              Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
              FilledButton.icon(
                icon: const Icon(Icons.compare_arrows),
                label: const Text('Compare'),
                onPressed: onCompare,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Picks which branches to draw beside the base branch.
class BranchPickerSheet extends ConsumerStatefulWidget {
  const BranchPickerSheet({super.key, required this.repo, required this.base, required this.initial});

  final RepoRef repo;
  final String base;
  final List<String> initial;

  @override
  ConsumerState<BranchPickerSheet> createState() => _BranchPickerSheetState();
}

class _BranchPickerSheetState extends ConsumerState<BranchPickerSheet> {
  late final _chosen = {...widget.initial};
  String _filter = '';

  @override
  Widget build(BuildContext context) {
    const max = FileHistoryNotifier.maxBranches;
    final theme = Theme.of(context);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (context, scroll) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(child: Text('Branches beside ${widget.base}', style: theme.textTheme.titleSmall)),
                Text('${_chosen.length}/$max', style: theme.textTheme.labelMedium),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              decoration: const InputDecoration(
                isDense: true,
                prefixIcon: Icon(Icons.search),
                hintText: 'Filter branches',
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() => _filter = v.toLowerCase()),
            ),
          ),
          Expanded(
            child: AsyncView(
              value: ref.watch(branchesProvider(widget.repo)),
              onRetry: () => ref.invalidate(branchesProvider(widget.repo)),
              data: (branches) {
                final names = [
                  for (final b in branches)
                    if (b.name != widget.base && b.name.toLowerCase().contains(_filter)) b.name,
                ];
                return ListView.builder(
                  controller: scroll,
                  itemCount: names.length,
                  itemBuilder: (context, i) {
                    final name = names[i];
                    final on = _chosen.contains(name);
                    return CheckboxListTile(
                      dense: true,
                      value: on,
                      title: Text(name, style: TextStyle(fontFamily: AppTheme.monoFamily)),
                      onChanged: on || _chosen.length < max
                          ? (v) => setState(() => v! ? _chosen.add(name) : _chosen.remove(name))
                          : null,
                    );
                  },
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Row(
                children: [
                  TextButton(onPressed: () => setState(_chosen.clear), child: const Text('Clear')),
                  const Spacer(),
                  FilledButton(onPressed: () => Navigator.pop(context, _chosen.toList()), child: const Text('Show')),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

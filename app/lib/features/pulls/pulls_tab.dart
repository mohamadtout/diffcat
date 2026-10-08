import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/layout/split_view.dart';
import '../../core/routing/routes.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/relative_time.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/common.dart';
import '../../data/github/models/models.dart';
import 'pull_screen.dart';
import 'pulls_providers.dart';

class PullsTab extends ConsumerStatefulWidget {
  const PullsTab({super.key, required this.repo});

  final RepoRef repo;

  @override
  ConsumerState<PullsTab> createState() => _PullsTabState();
}

class _PullsTabState extends ConsumerState<PullsTab> {
  String _state = 'open';
  int? _selected;

  @override
  Widget build(BuildContext context) {
    final key = (repo: widget.repo, state: _state);
    final split = SplitView.isActive(context);
    return SplitView(
      placeholder: 'Select a pull request',
      master: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'open', label: Text('Open')),
                ButtonSegment(value: 'closed', label: Text('Closed')),
                ButtonSegment(value: 'all', label: Text('All')),
              ],
              selected: {_state},
              onSelectionChanged: (s) => setState(() => _state = s.first),
            ),
          ),
          Expanded(
            child: AsyncView(
              value: ref.watch(pullListProvider(key)),
              onRetry: () => ref.invalidate(pullListProvider(key)),
              data: (pulls) => pulls.isEmpty
                  ? const EmptyView(icon: Icons.merge_type, message: 'No pull requests.')
                  : RefreshIndicator(
                      onRefresh: () => ref.refresh(pullListProvider(key).future),
                      child: ListView.builder(
                        itemCount: pulls.length,
                        itemBuilder: (context, i) {
                          final p = pulls[i];
                          return PullTile(
                            pull: p,
                            selected: split && p.number == _selected,
                            onTap: () => split
                                ? setState(() => _selected = p.number)
                                : context.push(Routes.pull(widget.repo, p.number)),
                          );
                        },
                      ),
                    ),
            ),
          ),
        ],
      ),
      detail: _selected == null ? null : PullView(key: ValueKey(_selected), repo: widget.repo, number: _selected!),
    );
  }
}

class PullTile extends StatelessWidget {
  const PullTile({super.key, required this.pull, required this.onTap, this.selected = false});

  final GhPull pull;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) => ListTile(
    selected: selected,
    selectedTileColor: Theme.of(context).colorScheme.secondaryContainer,
    leading: PullStateIcon(pull.state),
    title: Text(pull.title, maxLines: 2, overflow: TextOverflow.ellipsis),
    subtitle: Text(
      '#${pull.number} · ${pull.author.login} · ${pull.headRef} → ${pull.baseRef} · '
      '${relativeTime(pull.updatedAt)}',
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    ),
    trailing: UserAvatar(url: pull.author.avatarUrl, fallback: pull.author.login, size: 24),
    onTap: onTap,
  );
}

class PullStateIcon extends StatelessWidget {
  const PullStateIcon(this.state, {super.key});

  final PullState state;

  @override
  Widget build(BuildContext context) {
    final c = DiffColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    final (icon, color) = switch (state) {
      PullState.open => (Icons.merge_type, c.addFg),
      PullState.draft => (Icons.edit_note, scheme.outline),
      PullState.merged => (Icons.merge, Colors.purple),
      PullState.closed => (Icons.cancel_outlined, c.delFg),
    };
    return Icon(icon, color: color);
  }
}

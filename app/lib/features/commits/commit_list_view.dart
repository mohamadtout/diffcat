import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/relative_time.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/common.dart';
import '../../data/github/models/models.dart';
import 'commits_providers.dart';

/// Infinite-scrolling commit list. Used for branch history and file history.
class CommitListView extends ConsumerWidget {
  const CommitListView({super.key, required this.listKey, required this.onTap, this.selectedSha, this.header});

  final CommitListKey listKey;
  final ValueChanged<GhCommit> onTap;
  final String? selectedSha;
  final Widget? header;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = commitListProvider(listKey);
    final value = ref.watch(provider);
    return AsyncView(
      value: value,
      onRetry: () => ref.invalidate(provider),
      data: (paged) {
        if (paged.items.isEmpty) {
          return const EmptyView(icon: Icons.commit, message: 'No commits.');
        }
        final extra = header == null ? 0 : 1;
        return RefreshIndicator(
          onRefresh: () => ref.refresh(provider.future),
          child: NotificationListener<ScrollNotification>(
            onNotification: (n) {
              if (n.metrics.extentAfter < 600) {
                ref.read(provider.notifier).loadMore();
              }
              return false;
            },
            child: ListView.builder(
              itemCount: paged.items.length + extra + 1,
              itemBuilder: (context, i) {
                if (header != null && i == 0) return header!;
                final idx = i - extra;
                if (idx == paged.items.length) {
                  if (paged.loadMoreError != null) {
                    return ListTile(
                      leading: const Icon(Icons.error_outline),
                      title: const Text("Couldn't load more commits"),
                      trailing: TextButton(
                        onPressed: () => ref.read(provider.notifier).retryLoadMore(),
                        child: const Text('Retry'),
                      ),
                    );
                  }
                  return paged.hasMore
                      ? const Padding(
                          padding: EdgeInsets.all(16),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      : const SizedBox(height: 32);
                }
                final c = paged.items[idx];
                return CommitTile(commit: c, selected: c.sha == selectedSha, onTap: () => onTap(c));
              },
            ),
          ),
        );
      },
    );
  }
}

class CommitTile extends StatelessWidget {
  const CommitTile({super.key, required this.commit, required this.onTap, this.selected = false});

  final GhCommit commit;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      selected: selected,
      selectedTileColor: theme.colorScheme.secondaryContainer,
      leading: UserAvatar(url: commit.authorAvatarUrl, fallback: commit.authorLogin ?? commit.authorName),
      title: Text(commit.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Row(
        children: [
          if (commit.isMerge) ...[
            Icon(Icons.merge, size: 14, color: theme.colorScheme.outline),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              '${commit.authorLogin ?? commit.authorName} · ${relativeTime(commit.date)}',
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          ShaChip(commit.sha),
        ],
      ),
      onTap: onTap,
    );
  }
}

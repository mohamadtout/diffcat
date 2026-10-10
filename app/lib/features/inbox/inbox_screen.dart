import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/layout/readable_width.dart';
import '../../core/layout/split_view.dart';
import '../../core/routing/routes.dart';
import '../../core/utils/relative_time.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/common.dart';
import '../../data/github/models/models.dart';
import '../auth/auth_controller.dart';
import '../notifications/watch_controller.dart';
import '../pulls/pull_screen.dart';
import '../repos/repos_providers.dart';
import 'inbox_providers.dart';

/// Pull requests that need you, across every repo: review requests first.
class InboxScreen extends ConsumerStatefulWidget {
  const InboxScreen({super.key});

  @override
  ConsumerState<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends ConsumerState<InboxScreen> {
  var _section = InboxSection.reviewRequested;
  GhSearchPull? _selected;

  @override
  Widget build(BuildContext context) {
    if (!ref.watch(isSignedInProvider)) {
      return Scaffold(
        appBar: AppBar(title: const Text('Inbox')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const EmptyView(
                  icon: Icons.inbox_outlined,
                  message: 'Sign in to see pull requests waiting for your review, yours, and where you are mentioned.',
                ),
                FilledButton(onPressed: () => context.push(Routes.setup), child: const Text('Sign in')),
              ],
            ),
          ),
        ),
      );
    }
    final split = SplitView.isActive(context);
    final library = ref.watch(repoLibraryProvider);
    // Hidden repos and accounts never show (filtered here, so hiding one doesn't refetch).
    final value = ref
        .watch(inboxProvider(_section))
        .whenData(
          (r) => GhSearchResult([
            for (final p in r.items)
              if (!library.isHidden(p.repo.fullName)) p,
          ], total: r.total),
        );
    final selected = _selected;
    return Scaffold(
      appBar: AppBar(title: const Text('Inbox')),
      body: SplitView(
        placeholder: 'Select a pull request',
        master: Column(
          children: [
            SizedBox(
              height: 52,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                children: [
                  for (final s in InboxSection.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        avatar: Icon(s.icon, size: 18),
                        showCheckmark: false,
                        label: Text(s.label),
                        selected: s == _section,
                        onSelected: (_) => setState(() => _section = s),
                      ),
                    ),
                ],
              ),
            ),
            if (_section == InboxSection.reviewRequested) const _NotifyHint(),
            Expanded(
              child: AsyncView(
                value: value,
                onRetry: () => ref.invalidate(inboxProvider(_section)),
                data: (r) => RefreshIndicator(
                  onRefresh: () => ref.refresh(inboxProvider(_section).future),
                  child: r.items.isEmpty
                      ? ListView(
                          children: [
                            EmptyView(
                              icon: _section.icon,
                              message: _section == InboxSection.reviewRequested
                                  ? 'Nothing waiting for your review.'
                                  : 'No open pull requests here.',
                            ),
                          ],
                        )
                      : ReadableWidth(
                          builder: (sides) => ListView.builder(
                            padding: sides,
                            itemCount: r.items.length + (r.total > r.items.length ? 1 : 0),
                            itemBuilder: (context, i) {
                              if (i == r.items.length) {
                                return ListTile(
                                  dense: true,
                                  title: Text('${r.total - r.items.length} older ones on GitHub'),
                                );
                              }
                              final p = r.items[i];
                              return _InboxTile(
                                pull: p,
                                selected: split && selected?.key == p.key,
                                onTap: () =>
                                    split ? setState(() => _selected = p) : context.push(Routes.pull(p.repo, p.number)),
                              );
                            },
                          ),
                        ),
                ),
              ),
            ),
          ],
        ),
        detail: selected == null
            ? null
            : PullView(key: ValueKey(selected.key), repo: selected.repo, number: selected.number),
      ),
    );
  }
}

class _InboxTile extends StatelessWidget {
  const _InboxTile({required this.pull, required this.onTap, this.selected = false});

  final GhSearchPull pull;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      selected: selected,
      selectedTileColor: theme.colorScheme.secondaryContainer,
      leading: UserAvatar(url: pull.author.avatarUrl, fallback: pull.author.login),
      title: Text(pull.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${pull.repo.fullName} #${pull.number} · ${pull.author.login} · ${relativeTime(pull.updatedAt)}'
        '${pull.draft ? ' · draft' : ''}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: pull.comments == 0
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.chat_bubble_outline, size: 16, color: theme.colorScheme.outline),
                const SizedBox(width: 4),
                Text('${pull.comments}', style: theme.textTheme.labelMedium),
              ],
            ),
      onTap: onTap,
    );
  }
}

/// Offers review request notifications until they're on.
class _NotifyHint extends ConsumerWidget {
  const _NotifyHint();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(notifyReviewRequestsProvider)) return const SizedBox.shrink();
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: ListTile(
        leading: const Icon(Icons.notifications_active_outlined),
        title: const Text('Get notified about review requests and mentions'),
        trailing: TextButton(
          onPressed: () => ref.read(notifyReviewRequestsProvider.notifier).set(true),
          child: const Text('Turn on'),
        ),
      ),
    );
  }
}

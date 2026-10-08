import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/routing/routes.dart';
import '../../core/utils/relative_time.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/common.dart';
import '../../data/github/models/models.dart';
import '../commits/commit_list_view.dart';
import '../diff/diff_view.dart';
import 'pulls_providers.dart';
import 'pulls_tab.dart';

class PullScreen extends StatelessWidget {
  const PullScreen({super.key, required this.repo, required this.number});

  final RepoRef repo;
  final int number;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('${repo.name} #$number')),
    body: PullView(repo: repo, number: number),
  );
}

/// PR overview, file diffs and commits. Embeddable in split view.
class PullView extends ConsumerWidget {
  const PullView({super.key, required this.repo, required this.number});

  final RepoRef repo;
  final int number;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = (repo: repo, number: number);
    return AsyncView(
      value: ref.watch(pullProvider(key)),
      onRetry: () => ref.invalidate(pullProvider(key)),
      data: (pull) => DefaultTabController(
        length: 3,
        initialIndex: 1,
        child: Column(
          children: [
            _PullHeader(pull: pull),
            TabBar(
              tabs: [
                const Tab(text: 'Overview'),
                Tab(text: 'Files${pull.changedFiles == null ? '' : ' (${pull.changedFiles})'}'),
                Tab(text: 'Commits${pull.commits == null ? '' : ' (${pull.commits})'}'),
              ],
            ),
            Expanded(
              child: TabBarView(
                physics: const NeverScrollableScrollPhysics(), // diff pans horizontally
                children: [
                  _Overview(pull: pull),
                  AsyncView(
                    value: ref.watch(pullFilesProvider(key)),
                    onRetry: () => ref.invalidate(pullFilesProvider(key)),
                    data: (files) => DiffView(repo: repo, files: files, fileRef: pull.headSha),
                  ),
                  AsyncView(
                    value: ref.watch(pullCommitsProvider(key)),
                    onRetry: () => ref.invalidate(pullCommitsProvider(key)),
                    data: (commits) => ListView(
                      children: [
                        for (final c in commits)
                          CommitTile(commit: c, onTap: () => context.push(Routes.commit(repo, c.sha))),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PullHeader extends StatelessWidget {
  const _PullHeader({required this.pull});
  final GhPull pull;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PullStateIcon(pull.state),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(pull.title, style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  '${pull.author.login} wants to merge ${pull.headRef} → ${pull.baseRef}',
                  style: theme.textTheme.bodySmall,
                ),
                if (pull.additions != null) ...[
                  const SizedBox(height: 4),
                  LineCounts(additions: pull.additions!, deletions: pull.deletions ?? 0),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Overview extends StatelessWidget {
  const _Overview({required this.pull});
  final GhPull pull;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            UserAvatar(url: pull.author.avatarUrl, fallback: pull.author.login, size: 24),
            const SizedBox(width: 8),
            Text(
              'Opened ${relativeTime(pull.createdAt)} · updated ${relativeTime(pull.updatedAt)}',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
        const SizedBox(height: 16),
        SelectableText(pull.body.isEmpty ? 'No description provided.' : pull.body, style: theme.textTheme.bodyMedium),
      ],
    );
  }
}

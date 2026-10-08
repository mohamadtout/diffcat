import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/routing/routes.dart';
import '../../core/utils/relative_time.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/common.dart';
import '../../data/github/models/models.dart';
import '../diff/diff_view.dart';
import 'commits_providers.dart';

class CommitScreen extends ConsumerWidget {
  const CommitScreen({super.key, required this.repo, required this.sha, this.focusPath});

  final RepoRef repo;
  final String sha;
  final String? focusPath;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(
      title: Text(sha.length > 7 ? sha.substring(0, 7) : sha),
      actions: [
        IconButton(
          tooltip: 'Copy SHA',
          icon: const Icon(Icons.copy),
          onPressed: () => Clipboard.setData(ClipboardData(text: sha)),
        ),
      ],
    ),
    body: CommitView(repo: repo, sha: sha, focusPath: focusPath),
  );
}

/// Commit header + full diff. Embeddable in split view.
class CommitView extends ConsumerWidget {
  const CommitView({super.key, required this.repo, required this.sha, this.focusPath});

  final RepoRef repo;
  final String sha;
  final String? focusPath;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = commitProvider((repo: repo, sha: sha));
    return AsyncView(
      value: ref.watch(provider),
      onRetry: () => ref.invalidate(provider),
      data: (commit) => DiffView(
        key: ValueKey(commit.sha),
        repo: repo,
        files: commit.files,
        fileRef: commit.sha,
        focusPath: focusPath,
        header: CommitHeader(repo: repo, commit: commit),
      ),
    );
  }
}

class CommitHeader extends StatelessWidget {
  const CommitHeader({super.key, required this.repo, required this.commit});

  final RepoRef repo;
  final GhCommit commit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final adds = commit.additions ?? commit.files.fold<int>(0, (s, f) => s + f.additions);
    final dels = commit.deletions ?? commit.files.fold<int>(0, (s, f) => s + f.deletions);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(commit.title, style: theme.textTheme.titleMedium),
          if (commit.body.isNotEmpty) ...[
            const SizedBox(height: 8),
            SelectableText(commit.body, style: theme.textTheme.bodyMedium),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              UserAvatar(url: commit.authorAvatarUrl, fallback: commit.authorLogin ?? commit.authorName, size: 24),
              const SizedBox(width: 8),
              Expanded(
                child: Text('${commit.authorName} · ${fullTimestamp(commit.date)}', style: theme.textTheme.bodySmall),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ShaChip(commit.sha),
              Text('${commit.files.length} files', style: theme.textTheme.bodySmall),
              LineCounts(additions: adds, deletions: dels),
              for (final p in commit.parents)
                ActionChip(
                  visualDensity: VisualDensity.compact,
                  avatar: const Icon(Icons.arrow_upward, size: 14),
                  label: Text('parent ${p.substring(0, 7)}'),
                  onPressed: () => context.push(Routes.commit(repo, p)),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.difference_outlined, size: 18),
                label: const Text('Changed since this'),
                onPressed: () => context.push(Routes.changedSince(repo, base: commit.sha)),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.folder_open_outlined, size: 18),
                label: const Text('Browse at this commit'),
                onPressed: () => context.push(Routes.repo(repo, tab: 'files', ref: commit.sha)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

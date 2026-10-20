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
    // The app bar shows the SHA (and copies it), so the header doesn't repeat it.
    body: CommitView(repo: repo, sha: sha, focusPath: focusPath, showSha: false),
  );
}

/// Commit header + full diff. Embeddable in split view.
class CommitView extends ConsumerWidget {
  const CommitView({super.key, required this.repo, required this.sha, this.focusPath, this.showSha = true});

  final RepoRef repo;
  final String sha;
  final String? focusPath;

  /// Whether the header shows the SHA (off when an app bar already does).
  final bool showSha;

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
        header: CommitHeader(repo: repo, commit: commit, showSha: showSha),
      ),
    );
  }
}

/// The commit's summary above its diff, kept short so code shows on the first
/// screen: title, a two-line body ("More" opens the rest), one line of who,
/// when and how much, and one row of actions. It scrolls away with the diff.
class CommitHeader extends StatelessWidget {
  const CommitHeader({super.key, required this.repo, required this.commit, this.showSha = true});

  final RepoRef repo;
  final GhCommit commit;
  final bool showSha;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final adds = commit.additions ?? commit.files.fold<int>(0, (s, f) => s + f.additions);
    final dels = commit.deletions ?? commit.files.fold<int>(0, (s, f) => s + f.deletions);
    final files = commit.files.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(commit.title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
          if (commit.body.isNotEmpty) ...[const SizedBox(height: 4), ExpandableText(commit.body)],
          const SizedBox(height: 8),
          Row(
            children: [
              UserAvatar(url: commit.authorAvatarUrl, fallback: commit.authorLogin ?? commit.authorName, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Tooltip(
                  message: fullTimestamp(commit.date),
                  child: Text(
                    '${commit.authorName} · ${relativeTime(commit.date)} · $files file${files == 1 ? '' : 's'}',
                    style: theme.textTheme.bodySmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              LineCounts(additions: adds, deletions: dels),
            ],
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                if (showSha) ...[ShaChip(commit.sha), const SizedBox(width: 8)],
                for (final p in commit.parents) ...[
                  ActionChip(
                    avatar: const Icon(Icons.arrow_upward, size: 16),
                    label: Text('parent ${p.substring(0, 7)}'),
                    onPressed: () => context.push(Routes.commit(repo, p)),
                  ),
                  const SizedBox(width: 8),
                ],
                ActionChip(
                  avatar: const Icon(Icons.difference_outlined, size: 16),
                  label: const Text('Changed since this'),
                  onPressed: () => context.push(Routes.changedSince(repo, base: commit.sha)),
                ),
                const SizedBox(width: 8),
                ActionChip(
                  avatar: const Icon(Icons.folder_open_outlined, size: 16),
                  label: const Text('Browse at this commit'),
                  onPressed: () => context.push(Routes.repo(repo, tab: 'files', ref: commit.sha)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

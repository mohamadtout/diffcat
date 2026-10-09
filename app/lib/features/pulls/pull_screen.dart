import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/routing/routes.dart';
import '../../core/utils/relative_time.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/common.dart';
import '../../data/github/github_exception.dart';
import '../../data/github/models/models.dart';
import '../auth/auth_controller.dart';
import '../commits/commit_list_view.dart';
import '../diff/diff_parser.dart';
import '../diff/diff_view.dart';
import '../offline/offline_providers.dart';
import 'pulls_providers.dart';
import 'pulls_tab.dart';
import 'review.dart';
import 'review_providers.dart';
import 'review_widgets.dart';

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
                  _Overview(pull: pull, repo: repo),
                  AsyncView(
                    value: ref.watch(pullFilesProvider(key)),
                    onRetry: () => ref.invalidate(pullFilesProvider(key)),
                    data: (files) => _ReviewableDiff(pull: pull, pullKey: key, files: files),
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
            if (_canReview(ref, pull, repo)) ReviewBar(pullKey: key, headSha: pull.headSha),
          ],
        ),
      ),
    );
  }
}

/// Reviewing writes to GitHub: signed in, online, and only open PRs.
bool _canReview(WidgetRef ref, GhPull pull, RepoRef repo) =>
    ref.watch(isSignedInProvider) &&
    !ref.watch(isOfflineProvider(repo)) &&
    (pull.state == PullState.open || pull.state == PullState.draft);

/// The files diff with review threads and pending comments under their
/// lines; tapping a line comments on it.
class _ReviewableDiff extends ConsumerWidget {
  const _ReviewableDiff({required this.pull, required this.pullKey, required this.files});

  final GhPull pull;
  final PullKey pullKey;
  final List<GhFileChange> files;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canReview = _canReview(ref, pull, pullKey.repo);
    final comments = ref.watch(reviewCommentsProvider(pullKey)).value ?? const [];
    final threads = threadComments(comments).byLine;
    final draft = ref.watch(reviewDraftProvider(pullKey));
    final drafts = ref.read(reviewDraftProvider(pullKey).notifier);
    final api = ref.read(githubApiProvider);

    Future<void> post(Future<void> Function() call) async {
      final messenger = ScaffoldMessenger.of(context);
      try {
        await call();
        ref.invalidate(reviewCommentsProvider(pullKey));
      } on Object catch (e) {
        messenger.showSnackBar(SnackBar(content: Text("Couldn't post: ${e is GitHubException ? e.message : e}")));
      }
    }

    Future<void> comment(GhFileChange file, DiffLine line) async {
      final anchor = anchorFor(file.filename, line);
      if (anchor == null) return;
      final r = await showCommentComposer(
        context,
        title: '${file.basename}:${anchor.line}${anchor.side == DiffSide.left ? ' (removed)' : ''}',
      );
      if (r == null) return;
      if (r.action == ComposeAction.addToReview) {
        drafts.add(
          DraftComment(anchor: anchor, body: r.text),
          headSha: pull.headSha,
        );
      } else {
        await post(
          () => api.addReviewComment(
            pullKey.repo,
            pullKey.number,
            commitId: pull.headSha,
            path: anchor.path,
            line: anchor.line,
            side: anchor.side,
            body: r.text,
          ),
        );
      }
    }

    Future<void> reply(ReviewThread t) async {
      final r = await showCommentComposer(
        context,
        title: 'Reply to ${t.root.user.login}',
        actions: const [ComposeAction.commentNow],
      );
      if (r != null) await post(() => api.replyToReviewComment(pullKey.repo, pullKey.number, t.root.id, r.text));
    }

    Future<void> edit(DraftComment d) async {
      final r = await showCommentComposer(
        context,
        title: 'Edit pending comment',
        initial: d.body,
        actions: const [ComposeAction.save],
      );
      if (r != null) drafts.replace(d, DraftComment(anchor: d.anchor, body: r.text));
    }

    return DiffView(
      repo: pullKey.repo,
      files: files,
      fileRef: pull.headSha,
      onLineTap: canReview ? comment : null,
      lineFooter: (file, line) {
        final anchor = anchorFor(file.filename, line);
        if (anchor == null) return null;
        final t = threads[anchor] ?? const [];
        final d = draft.comments.where((c) => c.anchor == anchor).toList();
        if (t.isEmpty && d.isEmpty) return null;
        return LineComments(
          threads: t,
          drafts: d,
          onReply: canReview ? reply : null,
          onEditDraft: edit,
          onDeleteDraft: drafts.remove,
        );
      },
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
  const _Overview({required this.pull, required this.repo});
  final GhPull pull;
  final RepoRef repo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ReviewersSummary(pullKey: (repo: repo, number: pull.number)),
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

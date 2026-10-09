import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/relative_time.dart';
import '../../core/widgets/common.dart';
import '../../data/github/github_exception.dart';
import '../../data/github/models/models.dart';
import 'pulls_providers.dart';
import 'review.dart';
import 'review_providers.dart';

/// Review threads and pending comments under one diff line.
class LineComments extends StatelessWidget {
  const LineComments({
    super.key,
    required this.threads,
    required this.drafts,
    this.onReply,
    this.onEditDraft,
    this.onDeleteDraft,
  });

  final List<ReviewThread> threads;
  final List<DraftComment> drafts;
  final ValueChanged<ReviewThread>? onReply;
  final ValueChanged<DraftComment>? onEditDraft;
  final ValueChanged<DraftComment>? onDeleteDraft;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget card(Widget child, {Color? border}) => Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 6),
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: border ?? scheme.outlineVariant),
      ),
      child: child,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final t in threads)
          card(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final c in [t.root, ...t.replies]) _CommentBody(comment: c),
                if (onReply != null)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      icon: const Icon(Icons.reply, size: 18),
                      label: const Text('Reply'),
                      onPressed: () => onReply!(t),
                    ),
                  ),
              ],
            ),
          ),
        for (final d in drafts)
          card(
            border: scheme.tertiary,
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Chip(
                      label: const Text('Pending'),
                      visualDensity: VisualDensity.compact,
                      side: BorderSide(color: scheme.tertiary),
                    ),
                    const Spacer(),
                    if (onEditDraft != null)
                      IconButton(
                        tooltip: 'Edit',
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        onPressed: () => onEditDraft!(d),
                      ),
                    if (onDeleteDraft != null)
                      IconButton(
                        tooltip: 'Delete',
                        icon: const Icon(Icons.delete_outline, size: 18),
                        onPressed: () => onDeleteDraft!(d),
                      ),
                  ],
                ),
                Padding(padding: const EdgeInsets.only(bottom: 8), child: SelectableText(d.body)),
              ],
            ),
          ),
      ],
    );
  }
}

class _CommentBody extends StatelessWidget {
  const _CommentBody({required this.comment});

  final GhReviewComment comment;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              UserAvatar(url: comment.user.avatarUrl, fallback: comment.user.login, size: 20),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  '${comment.user.login} · ${relativeTime(comment.createdAt)}',
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          SelectableText(comment.body, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}

/// What the composer was closed with.
enum ComposeAction { addToReview, commentNow, save }

/// Writes a line comment. [actions]: the buttons offered (the first is the
/// main one). Returns null when cancelled.
Future<({String text, ComposeAction action})?> showCommentComposer(
  BuildContext context, {
  required String title,
  String initial = '',
  List<ComposeAction> actions = const [ComposeAction.addToReview, ComposeAction.commentNow],
}) => showModalBottomSheet<({String text, ComposeAction action})>(
  context: context,
  useRootNavigator: true,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => _Composer(title: title, initial: initial, actions: actions),
);

class _Composer extends StatefulWidget {
  const _Composer({required this.title, required this.initial, required this.actions});

  final String title;
  final String initial;
  final List<ComposeAction> actions;

  @override
  State<_Composer> createState() => _ComposerState();
}

class _ComposerState extends State<_Composer> {
  late final _text = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _done(ComposeAction a) {
    if (_text.text.trim().isEmpty) return;
    Navigator.pop(context, (text: _text.text.trim(), action: a));
  }

  @override
  Widget build(BuildContext context) {
    String label(ComposeAction a) => switch (a) {
      ComposeAction.addToReview => 'Add to review',
      ComposeAction.commentNow => 'Comment now',
      ComposeAction.save => 'Save',
    };
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.title, style: Theme.of(context).textTheme.titleSmall, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 8),
              TextField(
                controller: _text,
                autofocus: true,
                minLines: 3,
                maxLines: 8,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(hintText: 'Leave a comment (Markdown)', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 8),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final (i, a) in widget.actions.indexed.toList().reversed)
                    i == 0
                        ? FilledButton(onPressed: () => _done(a), child: Text(label(a)))
                        : OutlinedButton(onPressed: () => _done(a), child: Text(label(a))),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bottom bar of a pull request you can review: pending count and Review….
class ReviewBar extends ConsumerWidget {
  const ReviewBar({super.key, required this.pullKey, required this.headSha});

  final PullKey pullKey;
  final String headSha;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(reviewDraftProvider(pullKey));
    final theme = Theme.of(context);
    final n = draft.comments.length;
    return Material(
      color: theme.colorScheme.surfaceContainer,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 12, 6),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  n == 0 ? 'Tap a line to comment' : '$n pending comment${n == 1 ? '' : 's'}',
                  style: theme.textTheme.bodyMedium,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              FilledButton.icon(
                icon: const Icon(Icons.rate_review_outlined),
                label: const Text('Review'),
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  useRootNavigator: true,
                  isScrollControlled: true,
                  showDragHandle: true,
                  builder: (_) => ReviewSubmitSheet(pullKey: pullKey, headSha: headSha),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Summary, verdict and submit. The summary is saved with the draft as typed.
class ReviewSubmitSheet extends ConsumerStatefulWidget {
  const ReviewSubmitSheet({super.key, required this.pullKey, required this.headSha});

  final PullKey pullKey;
  final String headSha;

  @override
  ConsumerState<ReviewSubmitSheet> createState() => _ReviewSubmitSheetState();
}

class _ReviewSubmitSheetState extends ConsumerState<ReviewSubmitSheet> {
  late final _body = TextEditingController(text: ref.read(reviewDraftProvider(widget.pullKey)).body);
  var _event = ReviewEvent.comment;
  var _busy = false;
  String? _error;

  @override
  void dispose() {
    _body.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await ref.read(reviewDraftProvider(widget.pullKey).notifier).submit(_event, headSha: widget.headSha);
      navigator.pop();
      messenger.showSnackBar(SnackBar(content: Text('Review submitted: ${_event.label}')));
    } on Object catch (e) {
      if (mounted) setState(() => _error = e is GitHubException ? e.message : '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(reviewDraftProvider(widget.pullKey));
    final notifier = ref.read(reviewDraftProvider(widget.pullKey).notifier);
    final theme = Theme.of(context);
    final n = draft.comments.length;
    final outdated = draft.headSha != null && draft.headSha != widget.headSha;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Finish your review', style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                n == 0 ? 'No line comments.' : '$n line comment${n == 1 ? '' : 's'} will be posted with it.',
                style: theme.textTheme.bodySmall,
              ),
              if (outdated)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'New commits were pushed since you started. Your comments stay on the version you reviewed.',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.tertiary),
                  ),
                ),
              const SizedBox(height: 12),
              TextField(
                controller: _body,
                minLines: 3,
                maxLines: 8,
                onChanged: notifier.setBody,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(hintText: 'Summary (Markdown)', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              SegmentedButton<ReviewEvent>(
                segments: [for (final e in ReviewEvent.values) ButtonSegment(value: e, label: Text(e.label))],
                selected: {_event},
                onSelectionChanged: (s) => setState(() => _event = s.first),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                ),
              const SizedBox(height: 12),
              Row(
                children: [
                  if (!draft.isEmpty)
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () {
                              notifier.discard();
                              Navigator.pop(context);
                            },
                      child: const Text('Discard'),
                    ),
                  const Spacer(),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: _busy
                        ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Submit review'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Reviewers' current verdicts, for the PR overview.
class ReviewersSummary extends ConsumerWidget {
  const ReviewersSummary({super.key, required this.pullKey});

  final PullKey pullKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reviews = ref.watch(reviewsProvider(pullKey)).value;
    final comments = ref.watch(reviewCommentsProvider(pullKey)).value;
    if (reviews == null) return const SizedBox.shrink();
    final states = reviewerStates(reviews);
    final outdated = comments == null ? 0 : threadComments(comments).outdatedCount;
    final scheme = Theme.of(context).colorScheme;
    final c = DiffColors.of(context);
    if (states.isEmpty && outdated == 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Reviews', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final e in states.entries)
                Chip(
                  avatar: Icon(
                    switch (e.value) {
                      ReviewState.approved => Icons.check_circle,
                      ReviewState.changesRequested => Icons.cancel,
                      ReviewState.dismissed => Icons.remove_circle_outline,
                      _ => Icons.chat_bubble_outline,
                    },
                    size: 18,
                    color: switch (e.value) {
                      ReviewState.approved => c.addFg,
                      ReviewState.changesRequested => c.delFg,
                      _ => scheme.outline,
                    },
                  ),
                  label: Text(e.key),
                ),
            ],
          ),
          if (outdated > 0)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '$outdated comment thread${outdated == 1 ? '' : 's'} on code that has changed since (see GitHub).',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
        ],
      ),
    );
  }
}

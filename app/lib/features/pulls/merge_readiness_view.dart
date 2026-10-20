import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/routing/routes.dart';
import '../../core/theme/app_theme.dart';
import '../../data/github/models/models.dart';
import 'merge_readiness.dart';
import 'pulls_providers.dart';
import 'review.dart';
import 'review_providers.dart';

/// [pull]'s readiness from its checks and reviews, as they load. Errors (e.g.
/// offline without a download) leave that part unknown rather than failing.
MergeReadiness watchReadiness(WidgetRef ref, RepoRef repo, GhPull pull) {
  final checks = ref.watch(checkRunsProvider((repo: repo, sha: pull.headSha)));
  final reviews = ref.watch(reviewsProvider((repo: repo, number: pull.number))).value;
  return MergeReadiness.of(
    pull,
    checks: checks.value,
    checksUnavailable: checks.hasError,
    reviewers: reviews == null ? null : reviewerStates(reviews),
  );
}

(IconData, Color) _look(BuildContext context, Verdict v) {
  final s = StatusColors.from(context);
  return switch (v) {
    Verdict.ready => (Icons.check_circle, s.success),
    Verdict.blocked => (Icons.cancel, s.failure),
    Verdict.waiting => (Icons.timelapse, s.warning),
    Verdict.done => (Icons.info_outline, s.neutral),
  };
}

/// One line in the pull request header: "Ready to merge · 3 passed". Tapping
/// it opens the Overview tab, where [MergeReadinessCard] has the details.
class MergeReadinessLine extends ConsumerWidget {
  const MergeReadinessLine({super.key, required this.repo, required this.pull});

  final RepoRef repo;
  final GhPull pull;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = watchReadiness(ref, repo, pull);
    final (icon, color) = _look(context, r.verdict);
    final style = Theme.of(context).textTheme.bodySmall;
    return InkWell(
      onTap: () => DefaultTabController.maybeOf(context)?.animateTo(0),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                r.summary,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: style?.copyWith(color: color, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The merge readiness on the Overview tab: verdict, checks, conflicts and
/// reviews, each with its own icon (never color alone).
class MergeReadinessCard extends ConsumerWidget {
  const MergeReadinessCard({super.key, required this.repo, required this.pull});

  final RepoRef repo;
  final GhPull pull;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = watchReadiness(ref, repo, pull);
    final status = StatusColors.from(context);
    final theme = Theme.of(context);
    final (icon, color) = _look(context, r.verdict);
    final checks = r.checks;
    Widget row(IconData icon, Color color, String text, {VoidCallback? onTap}) => ListTile(
      dense: true,
      minLeadingWidth: 24,
      leading: Icon(icon, size: 20, color: color),
      title: Text(text),
      trailing: onTap == null ? null : const Icon(Icons.chevron_right),
      onTap: onTap,
    );
    return Card.outlined(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              leading: Icon(icon, color: color),
              title: Text(r.headline, style: theme.textTheme.titleMedium?.copyWith(color: color)),
            ),
            if (checks != null)
              row(
                checks.failed.isNotEmpty
                    ? Icons.cancel_outlined
                    : checks.running > 0
                    ? Icons.timelapse
                    : Icons.check_circle_outline,
                checks.failed.isNotEmpty
                    ? status.failure
                    : checks.running > 0
                    ? status.warning
                    : checks.total == 0
                    ? status.neutral
                    : status.success,
                'Checks: ${checks.label}',
                onTap: checks.total == 0 ? null : () => context.push(Routes.repo(repo, tab: 'actions')),
              ),
            if (r.merge case final merge?)
              row(
                pull.mergeableState == 'dirty' ? Icons.call_merge : Icons.merge_type,
                pull.mergeableState == 'dirty'
                    ? status.failure
                    : pull.mergeableState == 'behind'
                    ? status.warning
                    : status.success,
                merge,
              ),
            row(
              r.changesRequestedBy.isNotEmpty
                  ? Icons.rate_review_outlined
                  : r.approvedBy.isNotEmpty
                  ? Icons.verified_outlined
                  : Icons.person_search_outlined,
              r.changesRequestedBy.isNotEmpty
                  ? status.failure
                  : r.approvedBy.isNotEmpty
                  ? status.success
                  : status.neutral,
              r.reviews,
            ),
          ],
        ),
      ),
    );
  }
}

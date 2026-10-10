import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/relative_time.dart';
import '../../core/widgets/common.dart';
import '../../data/github/models/models.dart';
import '../offline/offline_chip.dart';

/// A repo row. Tapping it opens the repo online; downloaded repos also get an
/// "Offline" chip that opens them in offline mode.
///
/// In the repo list: [accent] is its folder's color, [selected] non-null
/// shows a checkbox (select mode), [onTap] replaces opening the repo.
class RepoTile extends ConsumerWidget {
  const RepoTile({
    super.key,
    required this.repo,
    this.watched = false,
    this.pinned = false,
    this.trailing,
    this.accent,
    this.selected,
    this.onTap,
    this.onLongPress,
  });

  final GhRepo repo;
  final bool watched;
  final bool pinned;
  final Widget? trailing;
  final Color? accent;
  final bool? selected;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final avatar = UserAvatar(url: repo.ownerAvatarUrl, fallback: repo.owner);
    return ListTile(
      selected: selected ?? false,
      leading: selected == null
          ? avatar
          : Icon(selected! ? Icons.check_circle : Icons.radio_button_unchecked, color: scheme.primary, size: 28),
      title: Row(
        children: [
          if (accent != null) ...[
            Container(
              width: 4,
              height: 16,
              decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(child: Text(repo.name, overflow: TextOverflow.ellipsis)),
          if (repo.isPrivate) ...[const SizedBox(width: 6), Icon(Icons.lock_outline, size: 14, color: scheme.outline)],
          if (pinned) ...[const SizedBox(width: 6), Icon(Icons.push_pin, size: 14, color: scheme.outline)],
          if (watched) ...[
            const SizedBox(width: 6),
            Icon(Icons.notifications_active_outlined, size: 14, color: scheme.primary),
          ],
          OfflineChip(repo: repo.ref),
        ],
      ),
      subtitle: Text(
        [
          repo.owner,
          ?repo.language,
          if (repo.pushedAt != null) relativeTime(repo.pushedAt!),
          if (repo.archived) 'archived on GitHub',
        ].join(' · '),
        overflow: TextOverflow.ellipsis,
      ),
      trailing: trailing,
      onTap: onTap ?? () => openRepo(context, ref, repo.ref),
      onLongPress: onLongPress,
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/routing/routes.dart';
import '../../data/github/models/models.dart';
import 'offline_providers.dart';

/// Opens [repo] online, or in offline mode (downloaded data only).
void openRepo(BuildContext context, WidgetRef ref, RepoRef repo, {bool offline = false}) {
  ref.read(offlineModeProvider.notifier).set(repo, offline: offline);
  context.push(Routes.repo(repo));
}

/// "Offline" indicator on a repo row; shown only when the repo has downloaded
/// data. Tapping it opens the repo in offline mode.
class OfflineChip extends ConsumerWidget {
  const OfflineChip({super.key, required this.repo});

  final RepoRef repo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(savedRepoProvider(repo.fullName)) == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Tooltip(
        message: 'Downloaded. Tap to open offline (downloaded data only)',
        child: Material(
          color: scheme.tertiaryContainer,
          shape: const StadiumBorder(),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: () => openRepo(context, ref, repo, offline: true),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.offline_pin, size: 14, color: scheme.onTertiaryContainer),
                  const SizedBox(width: 4),
                  Text(
                    'Offline',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(color: scheme.onTertiaryContainer),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

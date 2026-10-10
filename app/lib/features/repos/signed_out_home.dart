import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/routing/routes.dart';
import '../../core/widgets/common.dart';
import '../../data/github/models/models.dart';
import '../notifications/watch_controller.dart';
import '../offline/offline_chip.dart';
import '../offline/offline_providers.dart';
import 'repo_tile.dart';
import 'repos_providers.dart';

/// The repo list when signed out: open any public repo by name, plus the
/// downloaded and recently opened ones.
class SignedOutHome extends ConsumerStatefulWidget {
  const SignedOutHome({super.key});

  @override
  ConsumerState<SignedOutHome> createState() => _SignedOutHomeState();
}

class _SignedOutHomeState extends ConsumerState<SignedOutHome> {
  final _ctrl = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _open() {
    final repo = parseRepoInput(_ctrl.text);
    if (repo == null) {
      setState(() => _error = 'Use owner/name or a github.com URL');
      return;
    }
    setState(() => _error = null);
    openRepo(context, ref, repo);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final downloaded = ref.watch(savedReposInfoProvider).value ?? const <GhRepo>[];
    final downloadedNames = {for (final r in downloaded) r.fullName.toLowerCase()};
    final recentOnly = ref.watch(recentReposProvider).where((n) => !downloadedNames.contains(n.toLowerCase())).toList();
    final watched = ref.watch(watchedReposProvider);
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Browse any public repo', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'No account needed. Type owner/name or paste a github.com link.',
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _ctrl,
                    autocorrect: false,
                    enableSuggestions: false,
                    keyboardType: TextInputType.url,
                    textInputAction: TextInputAction.go,
                    decoration: InputDecoration(
                      hintText: 'flutter/flutter',
                      prefixIcon: const Icon(Icons.search),
                      border: const OutlineInputBorder(),
                      errorText: _error,
                    ),
                    onSubmitted: (_) => _open(),
                  ),
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: FilledButton(onPressed: _open, child: const Text('Open')),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Card.outlined(
              child: ListTile(
                leading: const Icon(Icons.lock_open_outlined),
                title: const Text('Sign in for your own and private repos'),
                subtitle: const Text('Optional. Also raises GitHub\'s limit from 60 to 5,000 requests an hour.'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push(Routes.setup),
              ),
            ),
            if (downloaded.isNotEmpty) ...[
              const SizedBox(height: 16),
              const SectionHeader('Downloaded', padding: EdgeInsets.zero),
              for (final r in downloaded) RepoTile(repo: r, watched: watched.contains(r.fullName.toLowerCase())),
            ],
            if (recentOnly.isNotEmpty) ...[
              const SizedBox(height: 16),
              const SectionHeader('Recent', padding: EdgeInsets.zero),
              for (final name in recentOnly)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: UserAvatar(fallback: name),
                  title: Row(
                    children: [
                      Flexible(child: Text(name, overflow: TextOverflow.ellipsis)),
                      if (watched.contains(name.toLowerCase())) ...[
                        const SizedBox(width: 6),
                        Icon(Icons.notifications_active_outlined, size: 14, color: theme.colorScheme.primary),
                      ],
                    ],
                  ),
                  trailing: IconButton(
                    tooltip: 'Remove from recent',
                    icon: const Icon(Icons.close),
                    onPressed: () => ref.read(recentReposProvider.notifier).remove(name),
                  ),
                  onTap: () {
                    final repo = parseRepoInput(name);
                    if (repo != null) openRepo(context, ref, repo);
                  },
                ),
            ],
          ],
        ),
      ),
    );
  }
}

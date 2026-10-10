import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/layout/readable_width.dart';
import '../../core/routing/routes.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/relative_time.dart';
import '../../core/widgets/async_view.dart';
import '../../data/github/models/models.dart';
import '../repos/repos_screen.dart';
import 'download_button.dart';
import 'offline_providers.dart';
import 'offline_store.dart';

Future<bool> _confirm(BuildContext context, String title, String message, {String action = 'Delete'}) async =>
    await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(action)),
        ],
      ),
    ) ??
    false;

/// Settings → Downloads: every offline copy and how much space it takes.
class DownloadsScreen extends ConsumerWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(offlineRevisionProvider);
    final store = ref.watch(offlineStoreProvider);
    final repos = store?.repos ?? const <SavedRepo>[];
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Downloads'),
        actions: [
          if (repos.isNotEmpty)
            IconButton(
              tooltip: 'Delete all downloads',
              icon: const Icon(Icons.delete_sweep_outlined),
              onPressed: () async {
                if (!await _confirm(context, 'Delete all downloads?', 'Frees ${formatBytes(store!.totalBytes)}.')) {
                  return;
                }
                for (final r in repos) {
                  await store.deleteRepo(r.fullName);
                }
              },
            ),
        ],
      ),
      body: store == null
          ? const EmptyView(
              icon: Icons.sd_card_alert_outlined,
              message: 'Offline storage is unavailable on this device.',
            )
          : repos.isEmpty
          ? const EmptyView(
              icon: Icons.download_for_offline_outlined,
              message: 'Nothing downloaded yet.\nOpen a repo and tap the download button to read it offline.',
            )
          : ReadableWidth(
              builder: (sides) => ListView(
                padding: sides,
                children: [
                  ListTile(
                    title: Text(formatBytes(store.totalBytes), style: theme.textTheme.headlineSmall),
                    subtitle: Text('${repos.length} repo${repos.length == 1 ? '' : 's'} saved on this device'),
                  ),
                  const Divider(),
                  for (final r in repos)
                    ListTile(
                      leading: const Icon(Icons.offline_pin_outlined),
                      title: Text(r.fullName),
                      subtitle: Text(
                        '${r.branches.length} branch${r.branches.length == 1 ? '' : 'es'} · '
                        'updated ${relativeTime(r.updatedAt)}',
                      ),
                      trailing: Text(formatBytes(r.bytes), style: theme.textTheme.titleSmall),
                      onTap: () {
                        final ref = parseRepoInput(r.fullName);
                        if (ref != null) context.push(Routes.savedRepo(ref));
                      },
                    ),
                ],
              ),
            ),
    );
  }
}

/// One repo's offline copy, broken down by branch, commit and pull request.
class SavedRepoScreen extends ConsumerWidget {
  const SavedRepoScreen({super.key, required this.repo});

  final RepoRef repo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final saved = ref.watch(savedRepoProvider(repo.fullName));
    final store = ref.watch(offlineStoreProvider);
    final downloads = ref.watch(downloadsProvider);
    final theme = Theme.of(context);
    final messenger = ScaffoldMessenger.of(context);
    if (saved == null || store == null) {
      return Scaffold(
        appBar: AppBar(title: Text(repo.fullName)),
        body: const EmptyView(icon: Icons.cloud_off, message: 'Not downloaded.'),
      );
    }
    final running = downloads.entries.where((e) => e.key.startsWith('${repo.fullName.toLowerCase()}@'));
    final sharedBytes = saved.groupBytes(Groups.repo) + saved.groupBytes(Groups.other);
    final pullBytes = {for (final n in saved.pulls.keys) n: saved.groupBytes(Groups.pull(n))};
    final orphanCommits = saved.entries.values
        .map((e) => e.group)
        .where((g) => g.startsWith('commit:'))
        .toSet()
        .difference({for (final b in saved.branches.values) ...b.commits.map((c) => Groups.commit(c.sha))});

    return Scaffold(
      appBar: AppBar(
        title: Text(repo.fullName),
        actions: [
          IconButton(
            tooltip: 'Open repo',
            icon: const Icon(Icons.open_in_new),
            onPressed: () => context.push(Routes.repo(repo)),
          ),
          IconButton(
            tooltip: 'Update all branches',
            icon: const Icon(Icons.sync),
            onPressed: () async {
              final error = await ref.read(downloadsProvider.notifier).updateRepo(repo);
              messenger.showSnackBar(SnackBar(content: Text(error == null ? 'Updated' : 'Update stopped: $error')));
            },
          ),
          IconButton(
            tooltip: 'Delete this download',
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              if (!await _confirm(context, 'Delete ${repo.fullName}?', 'Frees ${formatBytes(saved.bytes)}.')) return;
              await store.deleteRepo(repo.fullName);
              if (context.mounted) context.pop();
            },
          ),
        ],
      ),
      body: ReadableWidth(
        builder: (sides) => ListView(
          padding: sides + const EdgeInsets.only(bottom: 32),
          children: [
            ListTile(
              title: Text(formatBytes(saved.bytes), style: theme.textTheme.headlineSmall),
              subtitle: Text('Updated ${relativeTime(saved.updatedAt)}'),
            ),
            for (final r in running)
              if (!r.value.finished)
                ListTile(
                  leading: const SizedBox.square(dimension: 24, child: CircularProgressIndicator(strokeWidth: 2.5)),
                  title: Text('Downloading ${r.key.split('@').last}… ${r.value.phase}'),
                  subtitle: LinearProgressIndicator(value: r.value.fraction),
                ),
            if (saved.branches.isNotEmpty) const _Section('Branches'),
            for (final b in saved.branches.entries) _BranchTile(repo: repo, saved: saved, branch: b.key, info: b.value),
            if (saved.pulls.isNotEmpty) ...[
              const _Section('Pull requests'),
              for (final p in saved.pulls.entries)
                ListTile(
                  dense: true,
                  leading: Text('#${p.key}', style: theme.textTheme.labelLarge),
                  title: Text(p.value, overflow: TextOverflow.ellipsis),
                  subtitle: Text(formatBytes(pullBytes[p.key] ?? 0)),
                  trailing: IconButton(
                    tooltip: 'Delete this pull request',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => store.deletePull(repo.fullName, p.key),
                  ),
                ),
            ],
            const _Section('Other'),
            ListTile(
              dense: true,
              leading: const Icon(Icons.info_outline),
              title: const Text('Repository info, branch and pull request lists'),
              trailing: Text(formatBytes(sharedBytes)),
            ),
            if (orphanCommits.isNotEmpty)
              ListTile(
                dense: true,
                leading: const Icon(Icons.commit),
                title: Text('${orphanCommits.length} commits from deleted branches'),
                subtitle: Text(formatBytes(orphanCommits.fold(0, (s, g) => s + saved.groupBytes(g)))),
                trailing: IconButton(
                  tooltip: 'Delete them',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () async {
                    for (final g in orphanCommits) {
                      await store.deleteCommit(repo.fullName, g.substring('commit:'.length));
                    }
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title);
  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
    child: Text(
      title,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Theme.of(context).colorScheme.primary),
    ),
  );
}

class _BranchTile extends ConsumerWidget {
  const _BranchTile({required this.repo, required this.saved, required this.branch, required this.info});

  final RepoRef repo;
  final SavedRepo saved;
  final String branch;
  final SavedBranch info;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(offlineStoreProvider)!;
    final theme = Theme.of(context);
    final filesBytes = saved.groupBytes(Groups.files(branch));
    final savedCommits = info.commits.where((c) => saved.hasGroup(Groups.commit(c.sha))).length;
    return ExpansionTile(
      leading: const Icon(Icons.call_split),
      title: Text(branch),
      subtitle: Text(
        '${info.options.range == CommitRange.recent ? '' : '${info.options.rangeLabel} · '}'
        '$savedCommits/${info.commits.length} commits · '
        '${filesBytes > 0 ? 'all files ${formatBytes(filesBytes)}' : 'diffs only'} · '
        'updated ${relativeTime(info.updatedAt)}',
      ),
      trailing: Text(formatBytes(saved.branchBytes(branch)), style: theme.textTheme.titleSmall),
      childrenPadding: const EdgeInsets.only(bottom: 8),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              FilledButton.tonalIcon(
                icon: const Icon(Icons.sync, size: 18),
                label: const Text('Update'),
                onPressed: () => ref.read(downloadsProvider.notifier).start(repo, branch, info.options),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.tune, size: 18),
                label: const Text('Options'),
                onPressed: () => showDownloadSheet(context, repo: repo, branch: branch),
              ),
              if (filesBytes > 0)
                OutlinedButton.icon(
                  icon: const Icon(Icons.folder_delete_outlined, size: 18),
                  label: Text('Delete files (${formatBytes(filesBytes)})'),
                  onPressed: () => store.deleteBranchFiles(repo.fullName, branch),
                ),
              OutlinedButton.icon(
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('Delete branch'),
                onPressed: () async {
                  if (await _confirm(
                    context,
                    'Delete $branch?',
                    'Removes its file list, files and the diffs of its commits that no other saved branch has.',
                  )) {
                    await store.deleteBranch(repo.fullName, branch);
                  }
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        for (final c in info.commits)
          Builder(
            builder: (context) {
              final bytes = saved.groupBytes(Groups.commit(c.sha));
              return ListTile(
                dense: true,
                leading: Text(c.sha.substring(0, 7), style: TextStyle(fontFamily: AppTheme.monoFamily)),
                title: Text(c.title, overflow: TextOverflow.ellipsis),
                subtitle: Text(bytes == 0 ? 'not saved' : formatBytes(bytes)),
                trailing: bytes == 0
                    ? null
                    : IconButton(
                        tooltip: 'Delete this commit',
                        icon: const Icon(Icons.delete_outline, size: 20),
                        onPressed: () => store.deleteCommit(repo.fullName, c.sha),
                      ),
              );
            },
          ),
      ],
    );
  }
}

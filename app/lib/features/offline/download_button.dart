import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/routing/routes.dart';
import '../../core/utils/relative_time.dart';
import '../../data/github/models/models.dart';
import '../auth/auth_controller.dart';
import 'downloader.dart';
import 'offline_providers.dart';
import 'offline_store.dart';

/// App bar action for offline copies of one branch:
/// - not saved: download icon, opens the options sheet
/// - saved: update icon, updates right away (long-press for options)
/// - running: progress ring, opens the sheet with progress and Cancel
class DownloadButton extends ConsumerWidget {
  const DownloadButton({super.key, required this.repo, required this.branch});

  final RepoRef repo;
  final String branch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(offlineStoreProvider) == null) return const SizedBox.shrink();
    final saved = ref.watch(savedRepoProvider(repo.fullName))?.branches[branch];
    final progress = ref.watch(downloadsProvider)[downloadKey(repo, branch)];
    void openSheet() => showDownloadSheet(context, repo: repo, branch: branch);

    if (progress != null && !progress.finished) {
      return IconButton(
        tooltip: 'Downloading… ${progress.phase}',
        onPressed: openSheet,
        icon: SizedBox.square(
          dimension: 22,
          child: CircularProgressIndicator(strokeWidth: 2.5, value: progress.fraction),
        ),
      );
    }
    if (progress?.error != null) {
      return IconButton(
        tooltip: 'Download stopped: ${progress!.error}',
        icon: Icon(Icons.sync_problem, color: Theme.of(context).colorScheme.error),
        onPressed: openSheet,
      );
    }
    if (saved == null) {
      return IconButton(
        tooltip: 'Download for offline',
        icon: const Icon(Icons.download_for_offline_outlined),
        onPressed: openSheet,
      );
    }
    return GestureDetector(
      onLongPress: openSheet,
      child: IconButton(
        tooltip: 'Update offline copy (saved ${relativeTime(saved.updatedAt)}; long-press for options)',
        icon: const Icon(Icons.sync),
        onPressed: () {
          final messenger = ScaffoldMessenger.of(context);
          // Snackbars with an action stay up until closed, so close it when done.
          final updating = messenger.showSnackBar(
            SnackBar(
              content: Text('Updating offline copy of $branch…'),
              action: SnackBarAction(label: 'Options', onPressed: openSheet),
            ),
          );
          ref.read(downloadsProvider.notifier).start(repo, branch, saved.options).then((error) {
            updating.close();
            messenger.showSnackBar(
              SnackBar(content: Text(error == null ? 'Offline copy of $branch updated' : 'Update stopped: $error')),
            );
          });
        },
      ),
    );
  }
}

/// "saved 2h ago" for the repo title when [branch] has an offline copy.
String? savedLabel(WidgetRef ref, RepoRef repo, String branch) {
  final saved = ref.watch(savedRepoProvider(repo.fullName))?.branches[branch];
  return saved == null ? null : 'saved ${relativeTime(saved.updatedAt)}';
}

Future<void> showDownloadSheet(BuildContext context, {required RepoRef repo, required String branch}) =>
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _DownloadSheet(repo: repo, branch: branch),
    );

class _DownloadSheet extends ConsumerStatefulWidget {
  const _DownloadSheet({required this.repo, required this.branch});

  final RepoRef repo;
  final String branch;

  @override
  ConsumerState<_DownloadSheet> createState() => _DownloadSheetState();
}

class _DownloadSheetState extends ConsumerState<_DownloadSheet> {
  late DownloadOptions _options =
      ref.read(savedRepoProvider(widget.repo.fullName))?.branches[widget.branch]?.options ?? const DownloadOptions();

  String get _key => downloadKey(widget.repo, widget.branch);

  void _start() {
    ref.read(downloadsProvider.notifier).dismiss(_key);
    ref.read(downloadsProvider.notifier).start(widget.repo, widget.branch, _options);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final savedRepo = ref.watch(savedRepoProvider(widget.repo.fullName));
    final saved = savedRepo?.branches[widget.branch];
    final progress = ref.watch(downloadsProvider)[_key];
    final running = progress != null && !progress.finished;
    final signedIn = ref.watch(isSignedInProvider);
    final requests = 5 + (_options.commits / BranchDownloader.pageSize).ceil() + _options.commits;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(saved == null ? 'Download for offline' : 'Offline copy', style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              '${widget.repo.fullName} · ${widget.branch}'
              '${saved == null ? '' : ' · saved ${relativeTime(saved.updatedAt)} · ${formatBytes(savedRepo!.branchBytes(widget.branch))}'}',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            Text('Recent commits with their diffs', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 30, label: Text('30')),
                ButtonSegment(value: 100, label: Text('100')),
                ButtonSegment(value: 300, label: Text('300')),
              ],
              selected: {_options.commits},
              onSelectionChanged: running
                  ? null
                  : (s) => setState(() => _options = _options.copyWith(commits: s.first)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Open pull requests'),
              subtitle: const Text('Their diffs and commits'),
              value: _options.pulls,
              onChanged: running ? null : (v) => setState(() => _options = _options.copyWith(pulls: v)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('All files'),
              subtitle: Text(
                'Every text file at ${widget.branch}, as one archive download. Off: only diffs and the file '
                'list are saved, and opening a file needs the network.',
              ),
              value: _options.files,
              onChanged: running ? null : (v) => setState(() => _options = _options.copyWith(files: v)),
            ),
            const SizedBox(height: 4),
            Text(
              'About $requests GitHub requests${_options.pulls ? ', plus 3 per open pull request' : ''}. '
              'Commits already saved are skipped.'
              '${signedIn ? '' : ' Signed out, GitHub allows 60 requests an hour; sign in for bigger downloads.'}',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            if (running) ...[
              LinearProgressIndicator(value: progress.fraction),
              const SizedBox(height: 8),
              Text('${progress.phase} · ${progress.done}/${progress.total}', style: theme.textTheme.bodySmall),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () => ref.read(downloadsProvider.notifier).cancel(_key),
                child: const Text('Cancel'),
              ),
            ] else ...[
              if (progress?.error != null) ...[
                Text(
                  'Stopped during ${progress!.phase}: ${progress.error}. What was saved before that is kept.',
                  style: TextStyle(color: theme.colorScheme.error),
                ),
                const SizedBox(height: 12),
              ],
              FilledButton.icon(
                icon: Icon(saved == null ? Icons.download : Icons.sync),
                label: Text(saved == null ? 'Download' : 'Update'),
                onPressed: _start,
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  context.push(Routes.downloads);
                },
                child: const Text('Manage downloads'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

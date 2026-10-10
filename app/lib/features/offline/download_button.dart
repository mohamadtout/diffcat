import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/routing/routes.dart';
import '../../core/theme/app_theme.dart';
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

/// "saved 2h ago" for the repo title when [branch] is shown from its offline
/// copy (offline mode or data saver). Live screens don't need the age.
String? savedLabel(WidgetRef ref, RepoRef repo, String branch) {
  final saved = ref.watch(savedRepoProvider(repo.fullName))?.branches[branch];
  if (saved == null || !ref.watch(showsSavedCopyProvider(repo))) return null;
  return 'saved ${relativeTime(saved.updatedAt)}';
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
  late final _count = TextEditingController(text: '${_options.commits}');
  late final _since = TextEditingController(text: _options.since ?? '');

  String get _key => downloadKey(widget.repo, widget.branch);
  ({RepoRef repo, String branch}) get _target => (repo: widget.repo, branch: widget.branch);

  @override
  void dispose() {
    _count.dispose();
    _since.dispose();
    super.dispose();
  }

  static final _shaPattern = RegExp(r'^[0-9a-fA-F]{7,40}$');

  String? get _countError {
    final n = int.tryParse(_count.text.trim());
    return n == null || n < 1 || n > DownloadOptions.maxCommits ? '1 to ${DownloadOptions.maxCommits}' : null;
  }

  String? get _sinceError => _shaPattern.hasMatch(_since.text.trim()) ? null : 'A commit SHA: 7 to 40 hex characters';

  bool get _valid => switch (_options.range) {
    CommitRange.recent => _countError == null,
    CommitRange.since => _sinceError == null,
    CommitRange.all => true,
  };

  void _start() {
    final options = _options.copyWith(
      commits: int.tryParse(_count.text.trim()),
      since: _options.range == CommitRange.since ? _since.text.trim() : null,
    );
    setState(() => _options = options);
    ref.read(downloadsProvider.notifier).dismiss(_key);
    ref.read(downloadsProvider.notifier).start(widget.repo, widget.branch, options);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final savedRepo = ref.watch(savedRepoProvider(widget.repo.fullName));
    final saved = savedRepo?.branches[widget.branch];
    final progress = ref.watch(downloadsProvider)[_key];
    final running = progress != null && !progress.finished;
    final signedIn = ref.watch(isSignedInProvider);
    final total = _options.range == CommitRange.all ? ref.watch(commitCountProvider(_target)) : null;
    final files = _options.files ? ref.watch(filesEstimateProvider(_target)) : null;
    final remaining = ref.watch(githubApiProvider).client.rateLimitRemaining;

    // Repo, branches, tags, tree; then the commit list and diffs; PR lists; the archive.
    final commits = switch (_options.range) {
      CommitRange.recent => int.tryParse(_count.text.trim()),
      CommitRange.since => null,
      CommitRange.all => total?.value,
    };
    final requests = commits == null
        ? null
        : 4 +
              (commits / BranchDownloader.pageSize).ceil() +
              commits +
              switch (_options.pulls) {
                PullScope.none => 0,
                PullScope.open => 1,
                PullScope.openAndClosed => 3,
              } +
              (_options.files ? 1 : 0);
    final tooMany = requests != null && remaining != null && requests > remaining;

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
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
            Text('Commits with their diffs', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            SegmentedButton<CommitRange>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: CommitRange.recent, label: Text('Latest')),
                ButtonSegment(value: CommitRange.since, label: Text('Since…')),
                ButtonSegment(value: CommitRange.all, label: Text('All')),
              ],
              selected: {_options.range},
              onSelectionChanged: running ? null : (s) => setState(() => _options = _options.copyWith(range: s.first)),
            ),
            const SizedBox(height: 12),
            switch (_options.range) {
              CommitRange.recent => TextField(
                controller: _count,
                enabled: !running,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Number of commits',
                  helperText: 'The newest ones on ${widget.branch}',
                  errorText: _countError,
                  border: const OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
              CommitRange.since => TextField(
                controller: _since,
                enabled: !running,
                autocorrect: false,
                enableSuggestions: false,
                style: TextStyle(fontFamily: AppTheme.monoFamily),
                decoration: InputDecoration(
                  labelText: 'From commit',
                  hintText: 'a1b2c3d or a full SHA',
                  helperText: 'That commit and everything after it. Copy a SHA from a commit\'s screen.',
                  helperMaxLines: 2,
                  errorText: _since.text.isEmpty ? null : _sinceError,
                  border: const OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
              CommitRange.all => Text(switch (total) {
                AsyncData(:final value) => '${widget.branch} has ${_n(value)} commit${value == 1 ? '' : 's'}.',
                AsyncError() => "Couldn't count the commits.",
                _ => 'Counting commits…',
              }, style: muted),
            },
            const SizedBox(height: 16),
            Text('Pull requests', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            SegmentedButton<PullScope>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: PullScope.none, label: Text('None')),
                ButtonSegment(value: PullScope.open, label: Text('Open')),
                ButtonSegment(value: PullScope.openAndClosed, label: Text('Open & closed')),
              ],
              selected: {_options.pulls},
              onSelectionChanged: running ? null : (s) => setState(() => _options = _options.copyWith(pulls: s.first)),
            ),
            const SizedBox(height: 4),
            Text(
              'With their diffs, commits and review threads. Closed: the 30 most recently updated. '
              'Any single pull request can also be downloaded from its screen.',
              style: muted,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('All files'),
              subtitle: Text(switch (files) {
                null =>
                  'Every text file at ${widget.branch}, as one archive download. Off: only diffs and the file '
                      'list are saved, and opening a file needs the network.',
                AsyncData(:final value) =>
                  'About ${value.truncated ? 'at least ' : ''}${formatBytes(value.bytes)} '
                      'for ${_n(value.files)} text file${value.files == 1 ? '' : 's'} at ${widget.branch}, '
                      'as one archive download.',
                AsyncError() => 'Every text file at ${widget.branch}, as one archive download (size unknown).',
                _ => 'Estimating the size…',
              }),
              value: _options.files,
              onChanged: running ? null : (v) => setState(() => _options = _options.copyWith(files: v)),
            ),
            const SizedBox(height: 4),
            Text(
              '${requests == null ? 'One' : 'About ${_n(requests)}'} GitHub request${requests == 1 ? '' : 's'}'
              '${requests == null ? ' per commit up to that one, plus one per 30 for the list' : ''}'
              '${_options.pulls == PullScope.none ? '' : ', plus 5 per pull request'}. '
              'Commits already saved are skipped.'
              '${remaining == null ? '' : ' ${_n(remaining)} left this hour.'}'
              '${signedIn ? '' : ' Signed out, GitHub allows 60 requests an hour; sign in for bigger downloads.'}',
              style: muted,
            ),
            if (tooMany) ...[
              const SizedBox(height: 4),
              Text(
                'More than you have left this hour: the download stops when they run out and keeps what it saved. '
                'Update later to continue.',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
              ),
            ],
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
                onPressed: _valid ? _start : null,
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

/// 12,345
String _n(int n) => n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');

/// A download button for one pull request (its screen), open or closed.
/// Hidden in offline mode, where nothing can be fetched.
class PullDownloadButton extends ConsumerWidget {
  const PullDownloadButton({super.key, required this.repo, required this.number});

  final RepoRef repo;
  final int number;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(offlineStoreProvider) == null || ref.watch(isOfflineProvider(repo))) return const SizedBox.shrink();
    final saved = ref.watch(savedRepoProvider(repo.fullName))?.pulls.containsKey(number) ?? false;
    final progress = ref.watch(downloadsProvider)[pullDownloadKey(repo, number)];
    if (progress != null && !progress.finished) {
      return IconButton(
        tooltip: 'Downloading #$number…',
        onPressed: () => ref.read(downloadsProvider.notifier).cancel(pullDownloadKey(repo, number)),
        icon: SizedBox.square(
          dimension: 22,
          child: CircularProgressIndicator(strokeWidth: 2.5, value: progress.fraction),
        ),
      );
    }
    return IconButton(
      tooltip: saved ? 'Update the offline copy of #$number' : 'Download #$number for offline',
      icon: Icon(saved ? Icons.offline_pin_outlined : Icons.download_for_offline_outlined),
      onPressed: () async {
        final messenger = ScaffoldMessenger.of(context);
        final error = await ref.read(downloadsProvider.notifier).startPull(repo, number);
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              error == null
                  ? '#$number saved: its diff, commits and review threads open offline'
                  : 'Download stopped: $error',
            ),
          ),
        );
      },
    );
  }
}

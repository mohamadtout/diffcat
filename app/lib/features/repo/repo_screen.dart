import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/layout/breakpoints.dart';
import '../../core/routing/routes.dart';
import '../../core/widgets/async_view.dart';
import '../../data/github/github_exception.dart';
import '../../data/github/models/models.dart';
import '../auth/auth_controller.dart';
import '../commits/commits_tab.dart';
import '../console/console_tab.dart';
import '../files/file_tree_tab.dart';
import '../notifications/watch_controller.dart';
import '../offline/download_button.dart';
import '../offline/offline_providers.dart';
import '../pulls/pulls_tab.dart';
import '../repos/repos_providers.dart';
import 'ref_picker.dart';
import 'repo_providers.dart';

enum RepoTab {
  commits('Commits', Icons.commit),
  files('Files', Icons.folder_outlined),
  pulls('PRs', Icons.merge_type),
  console('Console', Icons.terminal);

  const RepoTab(this.label, this.icon);
  final String label;
  final IconData icon;

  static RepoTab parse(String? s) => RepoTab.values.asNameMap()[s] ?? commits;
}

/// Repo home: branch picker + Commits / Files / PRs / Console.
class RepoScreen extends ConsumerStatefulWidget {
  const RepoScreen({super.key, required this.repo, this.initialTab, this.initialRef});

  final RepoRef repo;
  final String? initialTab;
  final String? initialRef;

  @override
  ConsumerState<RepoScreen> createState() => _RepoScreenState();
}

class _RepoScreenState extends ConsumerState<RepoScreen> {
  late RepoTab _tab = RepoTab.parse(widget.initialTab);
  late String? _ref = widget.initialRef;
  late final Set<RepoTab> _visited = {_tab};

  @override
  void initState() {
    super.initState();
    // Remember successfully opened repos (typos and 404s are not recorded).
    ref.listenManual(repoProvider(widget.repo), fireImmediately: true, (_, next) {
      // Deferred: providers must not change while widgets are building.
      if (next.hasValue) Future.microtask(() => ref.read(recentReposProvider.notifier).add(widget.repo));
    });
  }

  void _select(RepoTab t) => setState(() {
    _tab = t;
    _visited.add(t);
  });

  Future<void> _toggleWatch() async {
    final notifier = ref.read(watchedReposProvider.notifier);
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (notifier.isWatched(widget.repo)) {
        await notifier.unwatch(widget.repo);
        messenger.showSnackBar(const SnackBar(content: Text('Notifications off for this repo')));
      } else {
        final msg = await notifier.watch(widget.repo);
        messenger.showSnackBar(SnackBar(content: Text(msg)));
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    final repoAsync = ref.watch(repoProvider(widget.repo));
    final compact = WindowSize.of(context) == WindowSize.compact;
    final watched = ref.watch(watchedReposProvider).contains(widget.repo.fullName.toLowerCase());
    final branch = _ref ?? repoAsync.value?.defaultBranch;
    final saved = branch == null ? null : savedLabel(ref, widget.repo, branch);
    final downloaded = ref.watch(savedRepoProvider(widget.repo.fullName)) != null;
    final offline = ref.watch(isOfflineProvider(widget.repo));
    void setOffline(bool value) => ref.read(offlineModeProvider.notifier).set(widget.repo, offline: value);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.repo.name, overflow: TextOverflow.ellipsis),
            Text(
              saved == null ? widget.repo.owner : '${widget.repo.owner} · $saved',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
        actions: [
          if (repoAsync.value case final repo?)
            RefPickerButton(
              repo: widget.repo,
              current: _ref ?? repo.defaultBranch,
              onSelected: (r) => setState(() => _ref = r),
            ),
          if (downloaded && !compact)
            IconButton(
              tooltip: offline ? 'Offline mode. Tap to go online' : 'Go offline (downloaded data only)',
              isSelected: offline,
              icon: const Icon(Icons.cloud_outlined),
              selectedIcon: const Icon(Icons.cloud_off),
              onPressed: () => setOffline(!offline),
            ),
          if (branch != null && !offline) DownloadButton(repo: widget.repo, branch: branch),
          if (!compact)
            IconButton(
              tooltip: 'Files changed since…',
              icon: const Icon(Icons.difference_outlined),
              onPressed: () => context.push(Routes.changedSince(widget.repo, ref: _ref)),
            ),
          IconButton(
            tooltip: watched ? 'Stop notifications' : 'Notify me of commits & PRs',
            icon: Icon(watched ? Icons.notifications_active : Icons.notifications_none),
            onPressed: _toggleWatch,
          ),
          // Phones: keep the title readable by moving the rarer actions here.
          if (compact)
            PopupMenuButton<String>(
              onSelected: (v) => switch (v) {
                'since' => context.push(Routes.changedSince(widget.repo, ref: _ref)),
                'offline' => setOffline(!offline),
                _ => null,
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'since',
                  child: ListTile(leading: Icon(Icons.difference_outlined), title: Text('Files changed since…')),
                ),
                if (downloaded)
                  PopupMenuItem(
                    value: 'offline',
                    child: ListTile(
                      leading: Icon(offline ? Icons.cloud_outlined : Icons.cloud_off),
                      title: Text(offline ? 'Go online' : 'Go offline (downloaded data only)'),
                    ),
                  ),
              ],
            ),
        ],
        bottom: compact
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(56),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: SegmentedButton<RepoTab>(
                    showSelectedIcon: false,
                    segments: [
                      for (final t in RepoTab.values) ButtonSegment(value: t, icon: Icon(t.icon), label: Text(t.label)),
                    ],
                    selected: {_tab},
                    onSelectionChanged: (s) => _select(s.first),
                  ),
                ),
              ),
      ),
      bottomNavigationBar: compact
          ? NavigationBar(
              height: 64,
              labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
              selectedIndex: _tab.index,
              onDestinationSelected: (i) => _select(RepoTab.values[i]),
              destinations: [for (final t in RepoTab.values) NavigationDestination(icon: Icon(t.icon), label: t.label)],
            )
          : null,
      body: Column(
        children: [
          if (offline) _OfflineBanner(onGoOnline: () => setOffline(false)),
          Expanded(child: _body(repoAsync)),
        ],
      ),
    );
  }

  Widget _body(AsyncValue<GhRepo> repoAsync) => AsyncView(
    value: repoAsync,
    onRetry: () => ref.invalidate(repoProvider(widget.repo)),
    error: (e) => e is GitHubException && (e.isNotFound || e.statusCode == 403)
        ? RepoUnavailableView(repo: widget.repo, onRetry: () => ref.invalidate(repoProvider(widget.repo)))
        : ErrorView(error: e, onRetry: () => ref.invalidate(repoProvider(widget.repo))),
    data: (repo) {
      final gitRef = _ref ?? repo.defaultBranch;
      // Tabs are built lazily on first visit, then kept alive.
      return IndexedStack(
        index: _tab.index,
        children: [
          for (final t in RepoTab.values)
            if (!_visited.contains(t))
              const SizedBox.shrink()
            else
              switch (t) {
                RepoTab.commits => CommitsTab(repo: widget.repo, gitRef: gitRef),
                RepoTab.files => FileTreeTab(repo: widget.repo, gitRef: gitRef),
                RepoTab.pulls => PullsTab(repo: widget.repo),
                RepoTab.console => ConsoleTab(repo: widget.repo, gitRef: gitRef),
              },
        ],
      );
    },
  );
}

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner({required this.onGoOnline});

  final VoidCallback onGoOnline;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
        child: Row(
          children: [
            Icon(Icons.cloud_off, size: 18, color: scheme.onTertiaryContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Offline mode: showing only downloaded data',
                style: TextStyle(color: scheme.onTertiaryContainer),
              ),
            ),
            TextButton(onPressed: onGoOnline, child: const Text('Go online')),
          ],
        ),
      ),
    );
  }
}

/// GitHub answers 404 (not 403) for private repos the token can't see, so
/// "not found" usually means "no access". Explain the likely causes instead
/// of a bare error.
class RepoUnavailableView extends ConsumerWidget {
  const RepoUnavailableView({super.key, required this.repo, required this.onRetry});

  final RepoRef repo;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final signedIn = ref.watch(isSignedInProvider);
    Widget bullet(String text) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('•  '),
          Expanded(child: Text(text)),
        ],
      ),
    );
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.lock_outline, size: 40, color: theme.colorScheme.error),
              const SizedBox(height: 12),
              Text("Can't open ${repo.fullName}", style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              if (!signedIn) ...[
                const Text(
                  "GitHub reports it as not found. Either it's private, or the owner/name is misspelled "
                  'or was renamed. Private repos need you to sign in.',
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  children: [
                    FilledButton(onPressed: () => context.push(Routes.setup), child: const Text('Sign in')),
                    FilledButton.tonal(onPressed: onRetry, child: const Text('Retry')),
                  ],
                ),
              ] else ...[
                const Text(
                  'GitHub reports it as not found. For a private repo this almost always means your token '
                  "can't see it. Common causes:",
                ),
                const SizedBox(height: 12),
                bullet(
                  'Fine-grained token (github_pat_…) and the repo belongs to another user: fine-grained tokens '
                  'only reach repos of the one account/org chosen when creating them. Use a classic token with '
                  'the "repo" scope instead.',
                ),
                bullet(
                  'Repo belongs to an organization: create the fine-grained token with that org as resource '
                  'owner (the org may need to approve it), or use a classic token. If the org uses SSO, '
                  'authorize the token for it.',
                ),
                bullet("You haven't accepted the collaborator invitation yet (check github.com/notifications)."),
                bullet('The owner/name is misspelled or the repo was renamed.'),
                const SizedBox(height: 8),
                Text(
                  'Change the token: Settings → Sign out, then paste the new one.',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                FilledButton.tonal(onPressed: onRetry, child: const Text('Retry')),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/layout/readable_width.dart';
import '../../core/routing/routes.dart';
import '../../core/storage/storage.dart';
import '../../core/utils/relative_time.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/common.dart';
import '../../data/github/models/models.dart';
import '../auth/auth_controller.dart';
import '../notifications/watch_controller.dart';
import '../offline/offline_chip.dart';
import '../offline/offline_providers.dart';

/// Your repositories, most recently pushed first (up to 150).
final myReposProvider = FutureProvider<List<GhRepo>>((ref) async {
  final api = ref.watch(githubApiProvider);
  final out = <GhRepo>[];
  for (var page = 1; page <= 3; page++) {
    final p = await api.myRepos(page: page);
    out.addAll(p.items);
    if (!p.hasNext) break;
  }
  return out;
});

final pinnedReposProvider = NotifierProvider<PinnedRepos, List<String>>(PinnedRepos.new);

class PinnedRepos extends Notifier<List<String>> {
  @override
  List<String> build() => ref.watch(sharedPrefsProvider).getStringList(StoreKeys.pinnedRepos) ?? const [];

  Future<void> toggle(String fullName) async {
    state = state.contains(fullName) ? (state.where((e) => e != fullName).toList()) : [...state, fullName];
    await ref.read(sharedPrefsProvider).setStringList(StoreKeys.pinnedRepos, state);
  }
}

/// Repos opened recently, newest first. The signed-out home screen lists them.
final recentReposProvider = NotifierProvider<RecentRepos, List<String>>(RecentRepos.new);

class RecentRepos extends Notifier<List<String>> {
  @override
  List<String> build() => ref.watch(sharedPrefsProvider).getStringList(StoreKeys.recentRepos) ?? const [];

  Future<void> add(RepoRef repo) => _save(pushRecent(state, repo.fullName));

  Future<void> remove(String fullName) => _save(state.where((e) => e != fullName).toList());

  Future<void> _save(List<String> list) async {
    state = list;
    await ref.read(sharedPrefsProvider).setStringList(StoreKeys.recentRepos, list);
  }
}

/// Moves [fullName] to the front (case-insensitively unique), keeping [max].
List<String> pushRecent(List<String> list, String fullName, {int max = 20}) =>
    [fullName, ...list.where((e) => e.toLowerCase() != fullName.toLowerCase())].take(max).toList();

class ReposScreen extends ConsumerStatefulWidget {
  const ReposScreen({super.key});

  @override
  ConsumerState<ReposScreen> createState() => _ReposScreenState();
}

class _ReposScreenState extends ConsumerState<ReposScreen> {
  String _query = '';

  Future<void> _openByName() async {
    final repo = await showDialog<RepoRef>(context: context, builder: (_) => const _OpenRepoDialog());
    if (repo != null && mounted) openRepo(context, ref, repo);
  }

  @override
  Widget build(BuildContext context) {
    if (!ref.watch(isSignedInProvider)) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Repositories'),
          actions: [TextButton(onPressed: () => context.push(Routes.setup), child: const Text('Sign in'))],
        ),
        body: const _SignedOutHome(),
      );
    }
    final repos = ref.watch(myReposProvider);
    final pinned = ref.watch(pinnedReposProvider);
    final watched = ref.watch(watchedReposProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Repositories'),
        actions: [IconButton(tooltip: 'Open by name', icon: const Icon(Icons.open_in_new), onPressed: _openByName)],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(64),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: SearchBar(
              hintText: 'Filter repositories',
              leading: const Icon(Icons.search),
              elevation: const WidgetStatePropertyAll(0),
              onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
            ),
          ),
        ),
      ),
      body: Builder(
        builder: (context) {
          final mine = repos.value;
          final all = mergeRepos(mine ?? const [], ref.watch(savedReposInfoProvider).value ?? const []);
          if (all.isEmpty) {
            if (repos.hasError) return ErrorView(error: repos.error!, onRetry: () => ref.invalidate(myReposProvider));
            if (repos.isLoading) return const Center(child: CircularProgressIndicator());
          }
          final filtered = all.where((r) => _query.isEmpty || r.fullName.toLowerCase().contains(_query)).toList()
            ..sort((a, b) {
              final pa = pinned.contains(a.fullName), pb = pinned.contains(b.fullName);
              return pa == pb ? 0 : (pa ? -1 : 1);
            });
          return RefreshIndicator(
            onRefresh: () => ref.refresh(myReposProvider.future),
            child: ReadableWidth(
              builder: (sides) => ListView(
                padding: sides,
                children: [
                  if (repos.isLoading && mine == null) const LinearProgressIndicator(),
                  // No network (or GitHub trouble): the downloads still work.
                  if (repos.hasError && mine == null)
                    ListTile(
                      leading: const Icon(Icons.cloud_off),
                      title: const Text("Can't reach GitHub"),
                      subtitle: const Text('Showing downloaded repos. Your other repos appear once you\'re online.'),
                      trailing: TextButton(
                        onPressed: () => ref.invalidate(myReposProvider),
                        child: const Text('Retry'),
                      ),
                    ),
                  if (filtered.isEmpty) const EmptyView(icon: Icons.inventory_2_outlined, message: 'No repositories.'),
                  for (final r in filtered)
                    RepoTile(
                      repo: r,
                      watched: watched.contains(r.fullName.toLowerCase()),
                      trailing: IconButton(
                        tooltip: pinned.contains(r.fullName) ? 'Unpin' : 'Pin to top',
                        icon: Icon(pinned.contains(r.fullName) ? Icons.push_pin : Icons.push_pin_outlined),
                        onPressed: () => ref.read(pinnedReposProvider.notifier).toggle(r.fullName),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Your repos followed by downloaded repos that aren't among them.
List<GhRepo> mergeRepos(List<GhRepo> mine, List<GhRepo> saved) {
  final names = {for (final r in mine) r.fullName.toLowerCase()};
  return [...mine, ...saved.where((r) => !names.contains(r.fullName.toLowerCase()))];
}

/// A repo row. Tapping it opens the repo online; downloaded repos also get an
/// "Offline" chip that opens them in offline mode.
class RepoTile extends ConsumerWidget {
  const RepoTile({super.key, required this.repo, this.watched = false, this.trailing});

  final GhRepo repo;
  final bool watched;
  final Widget? trailing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: UserAvatar(url: repo.ownerAvatarUrl, fallback: repo.owner),
      title: Row(
        children: [
          Flexible(child: Text(repo.name, overflow: TextOverflow.ellipsis)),
          if (repo.isPrivate) ...[const SizedBox(width: 6), Icon(Icons.lock_outline, size: 14, color: scheme.outline)],
          if (watched) ...[
            const SizedBox(width: 6),
            Icon(Icons.notifications_active_outlined, size: 14, color: scheme.primary),
          ],
          OfflineChip(repo: repo.ref),
        ],
      ),
      subtitle: Text(
        [repo.owner, ?repo.language, if (repo.pushedAt != null) relativeTime(repo.pushedAt!)].join(' · '),
        overflow: TextOverflow.ellipsis,
      ),
      trailing: trailing,
      onTap: () => openRepo(context, ref, repo.ref),
    );
  }
}

/// Home screen without a GitHub account: open any public repo by name or URL,
/// plus the ones opened recently.
class _SignedOutHome extends ConsumerStatefulWidget {
  const _SignedOutHome();

  @override
  ConsumerState<_SignedOutHome> createState() => _SignedOutHomeState();
}

class _SignedOutHomeState extends ConsumerState<_SignedOutHome> {
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
              Text('Downloaded', style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary)),
              for (final r in downloaded) RepoTile(repo: r, watched: watched.contains(r.fullName.toLowerCase())),
            ],
            if (recentOnly.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Recent', style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary)),
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

/// Parses `owner/name` or a github.com URL.
RepoRef? parseRepoInput(String input) {
  final m = RegExp(r'^\s*(?:https?://github\.com/)?([\w.-]+)/([\w.-]+?)(?:\.git)?/?\s*$').firstMatch(input);
  return m == null ? null : (owner: m.group(1)!, name: m.group(2)!);
}

/// Owns its TextEditingController so it is disposed only after the dialog's
/// exit animation finishes.
class _OpenRepoDialog extends StatefulWidget {
  const _OpenRepoDialog();

  @override
  State<_OpenRepoDialog> createState() => _OpenRepoDialogState();
}

class _OpenRepoDialogState extends State<_OpenRepoDialog> {
  final _ctrl = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final repo = parseRepoInput(_ctrl.text);
    if (repo == null) {
      setState(() => _error = 'Use owner/name or a github.com URL');
      return;
    }
    Navigator.pop(context, repo);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Open repository'),
    content: TextField(
      controller: _ctrl,
      autofocus: true,
      autocorrect: false,
      enableSuggestions: false,
      decoration: InputDecoration(hintText: 'owner/name', errorText: _error),
      onSubmitted: (_) => _submit(),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(onPressed: _submit, child: const Text('Open')),
    ],
  );
}

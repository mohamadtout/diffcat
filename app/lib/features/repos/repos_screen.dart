import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/layout/readable_width.dart';
import '../../core/routing/routes.dart';
import '../../core/utils/relative_time.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/common.dart';
import '../../data/github/models/models.dart';
import '../auth/auth_controller.dart';
import '../notifications/watch_controller.dart';
import '../offline/offline_chip.dart';
import '../offline/offline_providers.dart';
import 'repo_library.dart';
import 'repo_library_widgets.dart';
import 'repos_providers.dart';

class ReposScreen extends ConsumerStatefulWidget {
  const ReposScreen({super.key});

  @override
  ConsumerState<ReposScreen> createState() => _ReposScreenState();
}

class _ReposScreenState extends ConsumerState<ReposScreen> {
  String _query = '';

  /// Repos selected for a bulk action (`owner/name`); empty: not selecting.
  final _selected = <String>{};

  bool get _selecting => _selected.isNotEmpty;

  Future<void> _openByName() async {
    final repo = await showDialog<RepoRef>(context: context, builder: (_) => const _OpenRepoDialog());
    if (repo != null && mounted) openRepo(context, ref, repo);
  }

  void _toggle(String fullName) =>
      setState(() => _selected.contains(fullName) ? _selected.remove(fullName) : _selected.add(fullName));

  /// Applies a change to the library with a snackbar offering Undo.
  void _withUndo(String message, VoidCallback change) {
    final before = ref.read(repoLibraryProvider);
    final pinnedBefore = ref.read(pinnedReposProvider);
    change();
    setState(_selected.clear);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () {
              ref.read(repoLibraryProvider.notifier).set(before);
              ref.read(pinnedReposProvider.notifier).restore(pinnedBefore);
            },
          ),
        ),
      );
  }

  String _what(List<String> repos) => repos.length == 1 ? repos.single.split('/').last : '${repos.length} repos';

  void _archive(List<String> repos, {required bool archive}) =>
      _withUndo('${_what(repos)} ${archive ? 'archived' : 'unarchived'}', () {
        ref.read(repoLibraryProvider.notifier).update((l) => l.setArchived(repos, archive: archive));
        if (archive) ref.read(pinnedReposProvider.notifier).setPinned(repos, pinned: false);
      });

  void _hide(List<String> repos) {
    final watched = ref.read(watchedReposProvider);
    final unwatched = repos.where((r) => watched.contains(r.toLowerCase())).length;
    _withUndo(
      '${_what(repos)} hidden${unwatched == 0 ? '' : ', no longer watched'}. Unhide in Settings → Repository list.',
      () => ref.read(repoLibraryProvider.notifier).hide(repos),
    );
  }

  void _hideOwner(String owner) => _withUndo(
    'Everything from $owner hidden. Unhide in Settings → Repository list.',
    () => ref.read(repoLibraryProvider.notifier).hideOwner(owner),
  );

  Future<void> _move(List<String> repos) async {
    final message = await moveToFolder(context, ref, repos);
    if (message == null || !mounted) return;
    setState(_selected.clear);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _pin(List<String> repos) {
    final pins = ref.read(pinnedReposProvider.notifier);
    final pin = !repos.every(pins.isPinned);
    pins.setPinned(repos, pinned: pin);
    if (pin) ref.read(repoLibraryProvider.notifier).update((l) => l.setArchived(repos, archive: false));
    setState(_selected.clear);
  }

  PreferredSizeWidget _searchBar() => PreferredSize(
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
  );

  AppBar _appBar(RepoLibrary library, List<GhRepo> visible) {
    if (_selecting) {
      final repos = _selected.toList();
      final allPinned = repos.every(ref.read(pinnedReposProvider.notifier).isPinned);
      return AppBar(
        leading: IconButton(
          tooltip: 'Cancel selection',
          icon: const Icon(Icons.close),
          onPressed: () => setState(_selected.clear),
        ),
        title: Text('${_selected.length} selected'),
        actions: [
          IconButton(
            tooltip: 'Select all shown',
            icon: const Icon(Icons.select_all),
            onPressed: () => setState(() => _selected.addAll(visible.map((r) => r.fullName))),
          ),
          IconButton(
            tooltip: 'Move to folder',
            icon: const Icon(Icons.drive_file_move_outlined),
            onPressed: () => _move(repos),
          ),
          IconButton(
            tooltip: allPinned ? 'Unpin' : 'Pin to top',
            icon: Icon(allPinned ? Icons.push_pin : Icons.push_pin_outlined),
            onPressed: () => _pin(repos),
          ),
          PopupMenuButton<String>(
            tooltip: 'More',
            onSelected: (v) => switch (v) {
              'archive' => _archive(repos, archive: true),
              'unarchive' => _archive(repos, archive: false),
              _ => _hide(repos),
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'archive', child: Text('Archive')),
              PopupMenuItem(value: 'unarchive', child: Text('Unarchive')),
              PopupMenuItem(value: 'hide', child: Text('Hide')),
            ],
          ),
        ],
        bottom: _searchBar(),
      );
    }
    return AppBar(
      title: const Text('Repositories'),
      actions: [
        IconButton(tooltip: 'Open by name', icon: const Icon(Icons.open_in_new), onPressed: _openByName),
        PopupMenuButton<String>(
          tooltip: 'Organize',
          onSelected: (v) async {
            switch (v) {
              case 'select':
                if (visible.isNotEmpty) setState(() => _selected.add(visible.first.fullName));
              case 'folder':
                await createFolder(context, ref);
              case 'sort':
                ref
                    .read(repoLibraryProvider.notifier)
                    .update((l) => l.copyWith(sort: l.sort == RepoSort.pushed ? RepoSort.name : RepoSort.pushed));
              case 'settings':
                await context.push(Routes.repoList);
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'select', child: Text('Select repositories')),
            const PopupMenuItem(value: 'folder', child: Text('New folder…')),
            PopupMenuItem(
              value: 'sort',
              child: Text(library.sort == RepoSort.pushed ? 'Sort by name' : 'Sort by last push'),
            ),
            const PopupMenuItem(value: 'settings', child: Text('Folders, hidden and sources…')),
          ],
        ),
      ],
      bottom: _searchBar(),
    );
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
    final library = ref.watch(repoLibraryProvider);
    final mine = repos.value;
    final all = mergeRepos(mine ?? const [], ref.watch(savedReposInfoProvider).value ?? const []);
    final sections = library.arrange(all, pinned: pinned.toSet(), query: _query);
    final visible = [
      for (final s in sections)
        if (!s.collapsed) ...s.repos,
    ];
    final headers = library.folders.isNotEmpty || sections.length > 1;

    return PopScope(
      canPop: !_selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(_selected.clear);
      },
      child: Scaffold(
        appBar: _appBar(library, visible),
        body: Builder(
          builder: (context) {
            if (all.isEmpty) {
              if (repos.hasError) return ErrorView(error: repos.error!, onRetry: () => ref.invalidate(myReposProvider));
              if (repos.isLoading) return const Center(child: CircularProgressIndicator());
            }
            return RefreshIndicator(
              onRefresh: () => ref.refresh(myReposProvider.future),
              child: ReadableWidth(
                builder: (sides) => ListView(
                  padding: sides + const EdgeInsets.only(bottom: 24),
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
                    if (sections.every((s) => s.repos.isEmpty))
                      EmptyView(
                        icon: Icons.inventory_2_outlined,
                        message: _query.isNotEmpty
                            ? 'No repositories match.'
                            : library.sources.affiliation.isEmpty
                            ? 'No repositories: every source is off in Settings → Repository list.'
                            : 'No repositories.',
                      ),
                    for (final section in sections) ...[
                      if (headers && section.repos.isNotEmpty || section.kind == SectionKind.folder)
                        RepoSectionHeader(
                          section: section,
                          onToggle: switch (section.kind) {
                            SectionKind.folder =>
                              () => ref
                                  .read(repoLibraryProvider.notifier)
                                  .update((l) => l.toggleCollapsed(section.folder!.id)),
                            SectionKind.archived =>
                              () => ref
                                  .read(repoLibraryProvider.notifier)
                                  .update((l) => l.copyWith(archivedCollapsed: !l.archivedCollapsed)),
                            _ => null,
                          },
                          menu: section.folder == null ? null : _FolderMenu(folder: section.folder!),
                        ),
                      if (!section.collapsed)
                        for (final r in section.repos)
                          RepoTile(
                            repo: r,
                            watched: watched.contains(r.fullName.toLowerCase()),
                            pinned: section.kind == SectionKind.pinned,
                            accent: library.folderFor(r.fullName)?.color,
                            selected: _selecting ? _selected.contains(r.fullName) : null,
                            onTap: _selecting ? () => _toggle(r.fullName) : null,
                            onLongPress: () => _toggle(r.fullName),
                            trailing: _selecting
                                ? null
                                : _RepoMenu(
                                    repo: r,
                                    pinned: ref.read(pinnedReposProvider.notifier).isPinned(r.fullName),
                                    archived: library.isArchived(r),
                                    onPin: () => _pin([r.fullName]),
                                    onMove: () => _move([r.fullName]),
                                    onArchive: (archive) => _archive([r.fullName], archive: archive),
                                    onHide: () => _hide([r.fullName]),
                                    onHideOwner: () => _hideOwner(r.owner),
                                  ),
                          ),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Edit or delete a folder, from its heading.
class _FolderMenu extends ConsumerWidget {
  const _FolderMenu({required this.folder});

  final RepoFolder folder;

  @override
  Widget build(BuildContext context, WidgetRef ref) => PopupMenuButton<String>(
    tooltip: 'Folder options',
    icon: const Icon(Icons.more_vert, size: 20),
    onSelected: (v) async {
      final library = ref.read(repoLibraryProvider.notifier);
      if (v == 'edit') {
        final r = await showFolderDialog(context, initial: folder);
        if (r != null) library.update((l) => l.withFolder(folder.copyWith(name: r.name, color: r.color)));
      } else {
        library.update((l) => l.withoutFolder(folder.id));
        if (context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('${folder.name} deleted; its repos are back in Other')));
        }
      }
    },
    itemBuilder: (_) => const [
      PopupMenuItem(value: 'edit', child: Text('Rename or recolor')),
      PopupMenuItem(value: 'delete', child: Text('Delete folder')),
    ],
  );
}

/// One repo's actions in the list.
class _RepoMenu extends StatelessWidget {
  const _RepoMenu({
    required this.repo,
    required this.pinned,
    required this.archived,
    required this.onPin,
    required this.onMove,
    required this.onArchive,
    required this.onHide,
    required this.onHideOwner,
  });

  final GhRepo repo;
  final bool pinned;
  final bool archived;
  final VoidCallback onPin;
  final VoidCallback onMove;
  final ValueChanged<bool> onArchive;
  final VoidCallback onHide;
  final VoidCallback onHideOwner;

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
    tooltip: 'Repository options',
    onSelected: (v) => switch (v) {
      'pin' => onPin(),
      'move' => onMove(),
      'archive' => onArchive(!archived),
      'hide' => onHide(),
      _ => onHideOwner(),
    },
    itemBuilder: (_) => [
      PopupMenuItem(value: 'pin', child: Text(pinned ? 'Unpin' : 'Pin to top')),
      const PopupMenuItem(value: 'move', child: Text('Move to folder…')),
      // Archived on GitHub stays archived: there's nothing to undo here.
      if (!(repo.archived && archived))
        PopupMenuItem(value: 'archive', child: Text(archived ? 'Unarchive' : 'Archive')),
      const PopupMenuItem(value: 'hide', child: Text('Hide')),
      PopupMenuItem(value: 'owner', child: Text('Hide everything from ${repo.owner}')),
    ],
  );
}

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

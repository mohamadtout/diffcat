import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/layout/readable_width.dart';
import '../../core/routing/routes.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/text_input_dialog.dart';
import '../../data/github/models/models.dart';
import '../auth/auth_controller.dart';
import '../notifications/watch_controller.dart';
import '../offline/offline_chip.dart';
import '../offline/offline_providers.dart';
import 'repo_library.dart';
import 'repo_library_widgets.dart';
import 'repo_tile.dart';
import 'repos_providers.dart';
import 'signed_out_home.dart';

class ReposScreen extends ConsumerStatefulWidget {
  const ReposScreen({super.key});

  @override
  ConsumerState<ReposScreen> createState() => _ReposScreenState();
}

class _ReposScreenState extends ConsumerState<ReposScreen> {
  String _query = '';

  /// Repos selected for a bulk action, by [RepoLibrary.key]; empty: not selecting.
  final _selected = <String, GhRepo>{};

  bool get _selecting => _selected.isNotEmpty;

  Future<void> _openByName() async {
    final name = await askText(
      context,
      title: 'Open repository',
      action: 'Open',
      hint: 'owner/name',
      plain: true,
      validate: (t) => parseRepoInput(t) == null ? 'Use owner/name or a github.com URL' : null,
    );
    if (name != null && mounted) openRepo(context, ref, parseRepoInput(name)!);
  }

  void _toggle(GhRepo repo) {
    final key = RepoLibrary.key(repo.fullName);
    setState(() => _selected.remove(key) ?? (_selected[key] = repo));
  }

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
          // A snackbar with an action stays until tapped unless told otherwise.
          persist: false,
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

  String _what(List<GhRepo> repos) => repos.length == 1 ? repos.single.name : '${repos.length} repos';

  /// Archives or unarchives the [repos] that aren't that way already.
  void _archive(List<GhRepo> repos, {required bool archive}) {
    final library = ref.read(repoLibraryProvider);
    final changing = repos.where((r) => library.isArchived(r) != archive).toList();
    if (changing.isEmpty) return setState(_selected.clear);
    _withUndo('${_what(changing)} ${archive ? 'archived' : 'unarchived'}', () {
      ref.read(repoLibraryProvider.notifier).update((l) => l.setArchived(changing, archive: archive));
      if (archive) ref.read(pinnedReposProvider.notifier).setPinned(_names(changing), pinned: false);
    });
  }

  static List<String> _names(List<GhRepo> repos) => [for (final r in repos) r.fullName];

  void _hide(List<GhRepo> repos) {
    final watched = ref.read(watchedReposProvider);
    final unwatched = repos.where((r) => watched.contains(r.fullName.toLowerCase())).length;
    _withUndo(
      '${_what(repos)} hidden${unwatched == 0 ? '' : ', no longer watched'}. Unhide in Settings → Repository list.',
      () => ref.read(repoLibraryProvider.notifier).hide(_names(repos)),
    );
  }

  void _hideOwner(String owner) => _withUndo(
    'Everything from $owner hidden. Unhide in Settings → Repository list.',
    () => ref.read(repoLibraryProvider.notifier).hideOwner(owner),
  );

  Future<void> _move(List<GhRepo> repos) async {
    final message = await moveToFolder(context, ref, repos);
    if (message == null || !mounted) return;
    setState(_selected.clear);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _pin(List<GhRepo> repos) {
    final pins = ref.read(pinnedReposProvider.notifier);
    final pin = !repos.every((r) => pins.isPinned(r.fullName));
    pins.setPinned(_names(repos), pinned: pin);
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
      final repos = _selected.values.toList();
      final allPinned = repos.every((r) => ref.read(pinnedReposProvider.notifier).isPinned(r.fullName));
      final archived = repos.where(library.isArchived).length;
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
            onPressed: () =>
                setState(() => _selected.addAll({for (final r in visible) RepoLibrary.key(r.fullName): r})),
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
            // Only what applies; a mix of archived and active repos gets both.
            itemBuilder: (_) => [
              if (archived < repos.length) const PopupMenuItem(value: 'archive', child: Text('Archive')),
              if (archived > 0) const PopupMenuItem(value: 'unarchive', child: Text('Unarchive')),
              const PopupMenuItem(value: 'hide', child: Text('Hide')),
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
                if (visible.isNotEmpty) _toggle(visible.first);
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
        body: const SignedOutHome(),
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
                          menu: section.folder == null
                              ? null
                              : _FolderMenu(
                                  folder: section.folder!,
                                  index: library.folders.indexOf(section.folder!),
                                  count: library.folders.length,
                                ),
                        ),
                      if (!section.collapsed)
                        for (final r in section.repos)
                          RepoTile(
                            repo: r,
                            watched: watched.contains(r.fullName.toLowerCase()),
                            pinned: section.kind == SectionKind.pinned,
                            accent: library.folderFor(r.fullName)?.color,
                            selected: _selecting ? _selected.containsKey(RepoLibrary.key(r.fullName)) : null,
                            onTap: _selecting ? () => _toggle(r) : null,
                            onLongPress: () => _toggle(r),
                            trailing: _selecting
                                ? null
                                : _RepoMenu(
                                    repo: r,
                                    pinned: ref.read(pinnedReposProvider.notifier).isPinned(r.fullName),
                                    archived: library.isArchived(r),
                                    onPin: () => _pin([r]),
                                    onMove: () => _move([r]),
                                    onArchive: (archive) => _archive([r], archive: archive),
                                    onHide: () => _hide([r]),
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

/// Reorder, edit or delete a folder, from its heading.
class _FolderMenu extends ConsumerWidget {
  const _FolderMenu({required this.folder, required this.index, required this.count});

  final RepoFolder folder;

  /// Its place among [count] folders.
  final int index;
  final int count;

  @override
  Widget build(BuildContext context, WidgetRef ref) => PopupMenuButton<String>(
    tooltip: 'Folder options',
    icon: const Icon(Icons.more_vert, size: 20),
    onSelected: (v) async {
      final library = ref.read(repoLibraryProvider.notifier);
      if (v == 'up' || v == 'down') {
        library.update((l) => l.reorderFolder(index, v == 'up' ? index - 1 : index + 1));
      } else if (v == 'reorder') {
        await context.push(Routes.repoFolders);
      } else if (v == 'edit') {
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
    itemBuilder: (_) => [
      if (index > 0) const PopupMenuItem(value: 'up', child: Text('Move up')),
      if (index < count - 1) const PopupMenuItem(value: 'down', child: Text('Move down')),
      if (count > 2) const PopupMenuItem(value: 'reorder', child: Text('Reorder folders…')),
      const PopupMenuItem(value: 'edit', child: Text('Rename or recolor')),
      const PopupMenuItem(value: 'delete', child: Text('Delete folder')),
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
      PopupMenuItem(value: 'archive', child: Text(archived ? 'Unarchive' : 'Archive')),
      const PopupMenuItem(value: 'hide', child: Text('Hide')),
      PopupMenuItem(value: 'owner', child: Text('Hide everything from ${repo.owner}')),
    ],
  );
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/layout/readable_width.dart';
import '../../core/routing/routes.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/text_input_dialog.dart';
import 'repo_library.dart';
import 'repo_library_widgets.dart';
import 'repos_providers.dart';

/// Settings → Repository list: what's requested from GitHub, sort order,
/// folders, and the hidden repos and accounts.
class RepoListSettingsScreen extends ConsumerWidget {
  const RepoListSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final library = ref.watch(repoLibraryProvider);
    final notifier = ref.read(repoLibraryProvider.notifier);
    final theme = Theme.of(context);
    final sources = library.sources;
    void setSources(RepoSources s) => notifier.update((l) => l.copyWith(sources: s));

    return Scaffold(
      appBar: AppBar(title: const Text('Repository list')),
      body: ReadableWidth(
        builder: (sides) => ListView(
          padding: sides + const EdgeInsets.only(bottom: 32),
          children: [
            const SectionHeader('Load from GitHub'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Kinds turned off are never requested, so a big organization you don\'t need costs nothing.',
                style: theme.textTheme.bodySmall,
              ),
            ),
            SwitchListTile(
              title: const Text('Your repositories'),
              value: sources.owned,
              onChanged: (v) => setSources(sources.copyWith(owned: v)),
            ),
            SwitchListTile(
              title: const Text('Repositories you collaborate on'),
              value: sources.collaborations,
              onChanged: (v) => setSources(sources.copyWith(collaborations: v)),
            ),
            SwitchListTile(
              title: const Text('Your organizations\' repositories'),
              value: sources.organizations,
              onChanged: (v) => setSources(sources.copyWith(organizations: v)),
            ),

            const SectionHeader('Order'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SegmentedButton<RepoSort>(
                segments: const [
                  ButtonSegment(value: RepoSort.pushed, label: Text('Last push')),
                  ButtonSegment(value: RepoSort.name, label: Text('Name')),
                ],
                selected: {library.sort},
                onSelectionChanged: (s) => notifier.update((l) => l.copyWith(sort: s.first)),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.folder_outlined),
              title: const Text('Folders'),
              subtitle: Text(
                library.folders.isEmpty
                    ? 'None yet. Long-press repos in the list to file them.'
                    : library.folders.map((f) => f.name).join(', '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push(Routes.repoFolders),
            ),

            const SectionHeader('Hidden accounts'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Their repos never show, aren\'t watched and don\'t appear in notifications or the inbox. '
                'GitHub still includes them in the pages of your repo list.',
                style: theme.textTheme.bodySmall,
              ),
            ),
            for (final owner in library.hiddenOwners.toList()..sort())
              ListTile(
                leading: const Icon(Icons.visibility_off_outlined),
                title: Text(owner),
                trailing: TextButton(
                  onPressed: () => notifier.update((l) => l.setOwnerHidden(owner, hide: false)),
                  child: const Text('Unhide'),
                ),
              ),
            ListTile(
              leading: const Icon(Icons.person_off_outlined),
              title: const Text('Hide an account…'),
              onTap: () async {
                final login = await askText(
                  context,
                  title: 'Hide an account',
                  action: 'Hide',
                  label: 'User or organization',
                  hint: 'octo-org',
                  plain: true,
                  validate: (t) => RegExp(r'^@?[A-Za-z0-9-]+$').hasMatch(t) ? null : 'Letters, digits and hyphens only',
                );
                if (login != null) await notifier.hideOwner(login.replaceFirst('@', ''));
              },
            ),

            const SectionHeader('Hidden repositories'),
            if (library.hidden.isEmpty)
              const ListTile(
                leading: Icon(Icons.visibility_outlined),
                title: Text('None'),
                subtitle: Text('Hide a repo from its menu in the list.'),
              ),
            for (final repo in library.hidden.toList()..sort())
              ListTile(
                leading: const Icon(Icons.visibility_off_outlined),
                title: Text(repo),
                trailing: TextButton(
                  onPressed: () => notifier.update((l) => l.setHidden([repo], hide: false)),
                  child: const Text('Unhide'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Settings → Repository list → Folders: order, rename, recolor, delete.
class RepoFoldersScreen extends ConsumerWidget {
  const RepoFoldersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final library = ref.watch(repoLibraryProvider);
    final notifier = ref.read(repoLibraryProvider.notifier);
    final counts = <String, int>{};
    for (final id in library.folderOf.values) {
      counts[id] = (counts[id] ?? 0) + 1;
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Folders')),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.create_new_folder_outlined),
        label: const Text('New folder'),
        onPressed: () => createFolder(context, ref),
      ),
      body: library.folders.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'Folders group repos in the list, each with its own color. Create one here, or long-press '
                  'repos in the list and move them.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ReadableWidth(
              builder: (sides) => ReorderableListView(
                padding: sides + const EdgeInsets.only(bottom: 96),
                buildDefaultDragHandles: false,
                onReorderItem: (from, to) => notifier.update((l) => l.reorderFolder(from, to)),
                children: [
                  for (final (i, f) in library.folders.indexed)
                    ListTile(
                      key: ValueKey(f.id),
                      leading: ReorderableDragStartListener(
                        index: i,
                        child: const Icon(Icons.drag_handle, semanticLabel: 'Reorder'),
                      ),
                      title: Row(
                        children: [
                          FolderDot(f.color),
                          const SizedBox(width: 10),
                          Flexible(child: Text(f.name, overflow: TextOverflow.ellipsis)),
                        ],
                      ),
                      subtitle: Text('${counts[f.id] ?? 0} repos'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Rename or recolor',
                            icon: const Icon(Icons.edit_outlined),
                            onPressed: () async {
                              final r = await showFolderDialog(context, initial: f);
                              if (r == null) return;
                              notifier.update((l) => l.withFolder(f.copyWith(name: r.name, color: r.color)));
                            },
                          ),
                          IconButton(
                            tooltip: 'Delete folder (its repos go back to Other)',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => notifier.update((l) => l.withoutFolder(f.id)),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

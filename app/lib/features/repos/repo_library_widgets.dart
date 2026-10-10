import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/github/models/models.dart';
import 'repo_library.dart';
import 'repos_providers.dart';

/// A folder's color, as a small dot.
class FolderDot extends StatelessWidget {
  const FolderDot(this.color, {super.key, this.size = 12});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

/// Asks for a folder's name and color. [initial] edits an existing folder.
Future<({String name, Color color})?> showFolderDialog(BuildContext context, {RepoFolder? initial}) =>
    showDialog<({String name, Color color})>(
      context: context,
      builder: (_) => _FolderDialog(initial: initial),
    );

/// Owns its TextEditingController so it is disposed only after the dialog's
/// exit animation finishes.
class _FolderDialog extends StatefulWidget {
  const _FolderDialog({this.initial});

  final RepoFolder? initial;

  @override
  State<_FolderDialog> createState() => _FolderDialogState();
}

class _FolderDialogState extends State<_FolderDialog> {
  late final _name = TextEditingController(text: widget.initial?.name ?? '');
  late Color _color = widget.initial?.color ?? folderColors[6];

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isNotEmpty) Navigator.pop(context, (name: name, color: _color));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(widget.initial == null ? 'New folder' : 'Edit folder'),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _name,
            autofocus: true,
            maxLength: 40,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Name', hintText: 'Work, Clients, Side projects…'),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final c in folderColors)
                Semantics(
                  button: true,
                  selected: c == _color,
                  label: 'Color',
                  child: InkResponse(
                    onTap: () => setState(() => _color = c),
                    radius: 22,
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: c,
                        shape: BoxShape.circle,
                        border: Border.all(color: c == _color ? scheme.onSurface : Colors.transparent, width: 3),
                      ),
                      child: c == _color ? const Icon(Icons.check, size: 18, color: Colors.white) : null,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _submit, child: Text(widget.initial == null ? 'Create' : 'Save')),
      ],
    );
  }
}

/// Creates a folder (asking for name and color). Returns its id.
Future<String?> createFolder(BuildContext context, WidgetRef ref) async {
  final r = await showFolderDialog(context);
  return r == null ? null : ref.read(repoLibraryProvider.notifier).createFolder(r.name, r.color);
}

/// Lets the user pick a folder for [repos] (or none, or a new one) and moves
/// them there. Returns a message for a snackbar, or null if cancelled.
Future<String?> moveToFolder(BuildContext context, WidgetRef ref, List<GhRepo> repos) async {
  final library = ref.read(repoLibraryProvider);
  final current = repos.length == 1 ? library.folderOf[RepoLibrary.key(repos.single.fullName)] : null;
  final choice = await showModalBottomSheet<String>(
    context: context,
    useRootNavigator: true,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              alignment: AlignmentDirectional.centerStart,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                repos.length == 1 ? 'Move ${repos.single.name} to' : 'Move ${repos.length} repos to',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            for (final f in library.folders)
              ListTile(
                leading: FolderDot(f.color, size: 16),
                title: Text(f.name),
                trailing: f.id == current ? const Icon(Icons.check) : null,
                onTap: () => Navigator.pop(context, f.id),
              ),
            ListTile(
              leading: const Icon(Icons.folder_off_outlined),
              title: const Text('No folder'),
              trailing: current == null && repos.length == 1 ? const Icon(Icons.check) : null,
              onTap: () => Navigator.pop(context, ''),
            ),
            ListTile(
              leading: const Icon(Icons.create_new_folder_outlined),
              title: const Text('New folder…'),
              onTap: () => Navigator.pop(context, '+'),
            ),
          ],
        ),
      ),
    ),
  );
  if (choice == null || !context.mounted) return null;
  final folderId = switch (choice) {
    '' => null,
    '+' => await createFolder(context, ref),
    _ => choice,
  };
  if (choice == '+' && folderId == null) return null;
  ref.read(repoLibraryProvider.notifier).update((l) => l.move(repos, folderId));
  final name = folderId == null ? null : ref.read(repoLibraryProvider).folders.firstWhere((f) => f.id == folderId).name;
  final what = repos.length == 1 ? repos.single.name : '${repos.length} repos';
  return name == null ? '$what moved out of folders' : '$what moved to $name';
}

/// The heading of a section of the repo list; folders and Archived collapse.
class RepoSectionHeader extends StatelessWidget {
  const RepoSectionHeader({super.key, required this.section, this.onToggle, this.menu});

  final RepoSection section;
  final VoidCallback? onToggle;

  /// Folder actions (edit, delete).
  final Widget? menu;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final folder = section.folder;
    final (Widget icon, String label) = switch (section.kind) {
      SectionKind.pinned => (const Icon(Icons.push_pin_outlined, size: 16), 'Pinned'),
      SectionKind.folder => (FolderDot(folder!.color), folder.name),
      SectionKind.other => (const Icon(Icons.inventory_2_outlined, size: 16), 'Other'),
      SectionKind.archived => (const Icon(Icons.archive_outlined, size: 16), 'Archived'),
    };
    final collapsible = onToggle != null;
    return InkWell(
      onTap: onToggle,
      child: Padding(
        // The menu lines up with the repo rows' menus (ListTile's end padding).
        padding: EdgeInsets.fromLTRB(16, 12, menu == null ? 24 : 28, 4),
        child: Row(
          children: [
            SizedBox(width: 20, child: Center(child: icon)),
            const SizedBox(width: 12),
            // One flexible child: a Flexible label plus a Spacer would split the
            // free width and leave the menu mid-row.
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      label,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: folder?.color ?? theme.colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text('${section.repos.length}', style: theme.textTheme.labelMedium),
                ],
              ),
            ),
            if (collapsible)
              Icon(
                section.collapsed ? Icons.expand_more : Icons.expand_less,
                size: 20,
                semanticLabel: section.collapsed ? 'Expand' : 'Collapse',
              ),
            ?menu,
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/layout/split_view.dart';
import '../../core/routing/routes.dart';
import '../../core/widgets/async_view.dart';
import '../../data/github/models/models.dart';
import 'file_view_screen.dart';
import 'files_providers.dart';
import 'tree_builder.dart';

class FileTreeTab extends ConsumerStatefulWidget {
  const FileTreeTab({super.key, required this.repo, required this.gitRef});

  final RepoRef repo;
  final String gitRef;

  @override
  ConsumerState<FileTreeTab> createState() => _FileTreeTabState();
}

class _FileTreeTabState extends ConsumerState<FileTreeTab> {
  final Set<String> _expanded = {};
  final _search = TextEditingController();
  String _query = '';
  String? _selected;

  @override
  void didUpdateWidget(covariant FileTreeTab old) {
    super.didUpdateWidget(old);
    if (old.gitRef != widget.gitRef) _selected = null;
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _openFile(String path) {
    if (SplitView.isActive(context)) {
      setState(() => _selected = path);
    } else {
      context.push(Routes.file(widget.repo, path, widget.gitRef));
    }
  }

  @override
  Widget build(BuildContext context) {
    final key = (repo: widget.repo, ref: widget.gitRef);
    final value = ref.watch(treeProvider(key));
    return SplitView(
      placeholder: 'Select a file',
      master: AsyncView(
        value: value,
        onRetry: () => ref.invalidate(treeProvider(key)),
        data: (tree) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: SearchBar(
                controller: _search,
                hintText: 'Find file (${tree.fileCount})',
                leading: const Icon(Icons.search),
                elevation: const WidgetStatePropertyAll(0),
                trailing: [
                  if (_query.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => setState(() {
                        _search.clear();
                        _query = '';
                      }),
                    ),
                ],
                onChanged: (v) => setState(() => _query = v.trim()),
              ),
            ),
            if (tree.truncated)
              const ListTile(
                dense: true,
                leading: Icon(Icons.warning_amber),
                title: Text('Repository is very large; tree listing is truncated.'),
              ),
            Expanded(child: _query.isEmpty ? _buildTree(tree.root) : _buildSearch(tree.root)),
          ],
        ),
      ),
      detail: _selected == null
          ? null
          : FileView(key: ValueKey(_selected), repo: widget.repo, path: _selected!, gitRef: widget.gitRef),
    );
  }

  Widget _buildTree(TreeNode root) {
    final rows = flattenVisible(root, _expanded);
    final scheme = Theme.of(context).colorScheme;
    return ListView.builder(
      itemCount: rows.length,
      itemExtent: 44,
      itemBuilder: (context, i) {
        final v = rows[i];
        final n = v.node;
        final open = _expanded.contains(n.path);
        return InkWell(
          onTap: n.isSubmodule
              ? null
              : n.isDir
              ? () => setState(() => open ? _expanded.remove(n.path) : _expanded.add(n.path))
              : () => _openFile(n.path),
          child: Container(
            color: n.path == _selected ? scheme.secondaryContainer : null,
            padding: EdgeInsets.only(left: 8.0 + v.depth * 16, right: 12),
            child: Row(
              children: [
                SizedBox(
                  width: 20,
                  child: n.isDir ? Icon(open ? Icons.expand_more : Icons.chevron_right, size: 18) : null,
                ),
                Icon(
                  n.isSubmodule
                      ? Icons.link
                      : n.isDir
                      ? (open ? Icons.folder_open : Icons.folder)
                      : _fileIcon(n.name),
                  size: 20,
                  color: n.isDir ? scheme.primary : scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(v.label, overflow: TextOverflow.ellipsis)),
                if (!n.isDir && n.size != null)
                  Text(
                    _formatSize(n.size!),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(color: scheme.outline),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSearch(TreeNode root) {
    final hits = searchFiles(root, _query);
    if (hits.isEmpty) return const EmptyView(icon: Icons.search_off, message: 'No matching files.');
    return ListView.builder(
      itemCount: hits.length,
      itemBuilder: (context, i) {
        final n = hits[i];
        return ListTile(
          dense: true,
          leading: Icon(_fileIcon(n.name), size: 20),
          title: Text(n.name),
          subtitle: Text(n.path, overflow: TextOverflow.ellipsis),
          selected: n.path == _selected,
          onTap: () => _openFile(n.path),
        );
      },
    );
  }
}

IconData _fileIcon(String name) {
  final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
  return switch (ext) {
    'png' || 'jpg' || 'jpeg' || 'gif' || 'webp' || 'svg' || 'ico' => Icons.image_outlined,
    'md' || 'txt' || 'rst' => Icons.article_outlined,
    'json' || 'yaml' || 'yml' || 'toml' || 'xml' || 'lock' => Icons.data_object,
    _ => Icons.description_outlined,
  };
}

String _formatSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
}

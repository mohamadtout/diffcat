import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/layout/split_view.dart';
import '../../core/routing/routes.dart';
import '../../data/github/models/models.dart';
import '../commits/commit_list_view.dart';
import '../commits/commit_screen.dart';

/// Every commit that touched [path], newest first. Tapping one opens that
/// commit scrolled to (and highlighting) this file's diff.
class FileHistoryScreen extends StatefulWidget {
  const FileHistoryScreen({super.key, required this.repo, required this.path, required this.gitRef});

  final RepoRef repo;
  final String path;
  final String gitRef;

  @override
  State<FileHistoryScreen> createState() => _FileHistoryScreenState();
}

class _FileHistoryScreenState extends State<FileHistoryScreen> {
  String? _selected;

  @override
  Widget build(BuildContext context) {
    final split = SplitView.isActive(context);
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('File history'),
            Text(widget.path, style: Theme.of(context).textTheme.labelSmall, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
      body: SplitView(
        placeholder: 'Select a commit',
        master: CommitListView(
          listKey: (repo: widget.repo, ref: widget.gitRef, path: widget.path),
          selectedSha: split ? _selected : null,
          header: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              'Renames are not followed: history before a rename appears under the old path.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.outline),
            ),
          ),
          onTap: (c) => split
              ? setState(() => _selected = c.sha)
              : context.push(Routes.commit(widget.repo, c.sha, file: widget.path)),
        ),
        detail: _selected == null
            ? null
            : CommitView(key: ValueKey(_selected), repo: widget.repo, sha: _selected!, focusPath: widget.path),
      ),
    );
  }
}

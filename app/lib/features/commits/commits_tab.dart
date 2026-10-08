import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/layout/split_view.dart';
import '../../core/routing/routes.dart';
import '../../data/github/models/models.dart';
import 'commit_list_view.dart';
import 'commit_screen.dart';

class CommitsTab extends StatefulWidget {
  const CommitsTab({super.key, required this.repo, required this.gitRef});

  final RepoRef repo;
  final String gitRef;

  @override
  State<CommitsTab> createState() => _CommitsTabState();
}

class _CommitsTabState extends State<CommitsTab> {
  String? _selected;

  @override
  void didUpdateWidget(covariant CommitsTab old) {
    super.didUpdateWidget(old);
    if (old.gitRef != widget.gitRef) _selected = null;
  }

  @override
  Widget build(BuildContext context) {
    final split = SplitView.isActive(context);
    return SplitView(
      placeholder: 'Select a commit to review its changes',
      master: CommitListView(
        listKey: (repo: widget.repo, ref: widget.gitRef, path: null),
        selectedSha: split ? _selected : null,
        onTap: (c) => split ? setState(() => _selected = c.sha) : context.push(Routes.commit(widget.repo, c.sha)),
      ),
      detail: _selected == null ? null : CommitView(key: ValueKey(_selected), repo: widget.repo, sha: _selected!),
    );
  }
}

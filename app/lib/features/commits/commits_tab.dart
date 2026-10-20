import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/layout/split_view.dart';
import '../../core/routing/routes.dart';
import '../../data/github/models/models.dart';
import '../offline/offline_providers.dart';
import 'commit_list_view.dart';
import 'commit_screen.dart';
import 'commits_providers.dart';

class CommitsTab extends ConsumerStatefulWidget {
  const CommitsTab({super.key, required this.repo, required this.gitRef});

  final RepoRef repo;
  final String gitRef;

  @override
  ConsumerState<CommitsTab> createState() => _CommitsTabState();
}

class _CommitsTabState extends ConsumerState<CommitsTab> {
  String? _selected;

  @override
  void didUpdateWidget(covariant CommitsTab old) {
    super.didUpdateWidget(old);
    if (old.gitRef != widget.gitRef) _selected = null;
  }

  @override
  Widget build(BuildContext context) {
    final split = SplitView.isActive(context);
    final listKey = (repo: widget.repo, ref: widget.gitRef, path: null);
    SplitView.autoSelect(
      context,
      current: _selected,
      first: ref.watch(commitListProvider(listKey)).value?.items.firstOrNull?.sha,
      enabled: !ref.watch(dataSaverProvider),
      select: (sha) => setState(() => _selected ??= sha),
    );
    return SplitView(
      placeholder: 'Select a commit to review its changes',
      master: CommitListView(
        listKey: listKey,
        selectedSha: split ? _selected : null,
        onTap: (c) => split ? setState(() => _selected = c.sha) : context.push(Routes.commit(widget.repo, c.sha)),
      ),
      detail: _selected == null ? null : CommitView(key: ValueKey(_selected), repo: widget.repo, sha: _selected!),
    );
  }
}

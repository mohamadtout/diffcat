import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/routing/routes.dart';
import '../../core/widgets/async_view.dart';
import '../../data/github/models/models.dart';
import '../commits/commit_list_view.dart';
import '../commits/commits_providers.dart';
import '../diff/diff_view.dart';

/// `git diff base...head` — also the target of multi-commit push
/// notifications.
class CompareScreen extends ConsumerWidget {
  const CompareScreen({super.key, required this.repo, required this.base, required this.head, this.focusPath});

  final RepoRef repo;
  final String base;
  final String head;
  final String? focusPath;

  String _short(String s) => s.length == 40 ? s.substring(0, 7) : s;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = (repo: repo, base: base, head: head);
    return Scaffold(
      appBar: AppBar(title: Text('${_short(base)}…${_short(head)}')),
      body: AsyncView(
        value: ref.watch(compareProvider(key)),
        onRetry: () => ref.invalidate(compareProvider(key)),
        data: (cmp) => DiffView(
          repo: repo,
          files: cmp.files,
          fileRef: head,
          focusPath: focusPath,
          header: ExpansionTile(
            leading: const Icon(Icons.commit),
            title: Text('${cmp.totalCommits} commits'),
            subtitle: cmp.commits.length < cmp.totalCommits ? Text('Showing first ${cmp.commits.length}') : null,
            children: [
              for (final c in cmp.commits.reversed)
                CommitTile(commit: c, onTap: () => context.push(Routes.commit(repo, c.sha))),
            ],
          ),
        ),
      ),
    );
  }
}

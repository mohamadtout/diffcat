import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/github/models/models.dart';
import '../auth/auth_controller.dart';
import 'tree_builder.dart';

typedef TreeKey = ({RepoRef repo, String ref});

class RepoTree {
  const RepoTree(this.root, {required this.truncated, required this.fileCount});

  final TreeNode root;
  final bool truncated;
  final int fileCount;
}

final treeProvider = FutureProvider.autoDispose.family<RepoTree, TreeKey>((ref, k) async {
  final tree = await ref.watch(githubApiProvider).tree(k.repo, k.ref);
  return RepoTree(
    buildTree(tree.entries),
    truncated: tree.truncated,
    fileCount: tree.entries.where((e) => e.type == TreeEntryType.blob).length,
  );
});

typedef FileKey = ({RepoRef repo, String path, String ref});

final fileContentProvider = FutureProvider.autoDispose.family<String, FileKey>(
  (ref, k) => ref.watch(githubApiProvider).fileContent(k.repo, k.path, k.ref),
);

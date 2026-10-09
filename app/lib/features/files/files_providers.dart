import 'dart:isolate';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/github/github_exception.dart';
import '../../data/github/models/models.dart';
import '../auth/auth_controller.dart';
import '../offline/offline_providers.dart';
import 'tree_builder.dart';

typedef TreeKey = ({RepoRef repo, String ref});

class RepoTree {
  const RepoTree(this.root, {required this.truncated, required this.fileCount});

  final TreeNode root;
  final bool truncated;
  final int fileCount;
}

/// Trees bigger than this are built on a background isolate: a monorepo's
/// 100k entries would otherwise freeze the UI for a moment.
const _isolateTreeEntries = 5000;

final treeProvider = FutureProvider.autoDispose.family<RepoTree, TreeKey>((ref, k) async {
  final tree = await ref.watch(githubApiProvider).tree(k.repo, k.ref);
  final entries = tree.entries;
  return RepoTree(
    entries.length > _isolateTreeEntries ? await Isolate.run(() => buildTree(entries)) : buildTree(entries),
    truncated: tree.truncated,
    fileCount: tree.entries.where((e) => e.type == TreeEntryType.blob).length,
  );
});

typedef FileKey = ({RepoRef repo, String path, String ref});

final fileContentProvider = FutureProvider.autoDispose.family<String, FileKey>(
  (ref, k) => ref.watch(githubApiProvider).fileContent(k.repo, k.path, k.ref),
);

/// Who last changed each line of a file. Needs a token (GraphQL), and isn't
/// part of offline copies.
final blameProvider = FutureProvider.autoDispose.family<List<BlameRange>, FileKey>((ref, k) {
  if (ref.watch(isOfflineProvider(k.repo))) throw GitHubException.notDownloaded();
  return ref.watch(githubApiProvider).blame(k.repo, k.path, k.ref);
});

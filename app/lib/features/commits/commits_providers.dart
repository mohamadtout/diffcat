import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/github/models/models.dart';
import '../auth/auth_controller.dart';
import '../repo/repo_providers.dart';

/// [path] non-null turns the list into a single file's history.
typedef CommitListKey = ({RepoRef repo, String ref, String? path});

final commitListProvider = AsyncNotifierProvider.autoDispose.family<CommitListNotifier, Paged<GhCommit>, CommitListKey>(
  CommitListNotifier.new,
);

class CommitListNotifier extends AsyncNotifier<Paged<GhCommit>> {
  CommitListNotifier(this.key);
  final CommitListKey key;

  static const _perPage = 30;

  @override
  Future<Paged<GhCommit>> build() async {
    final page = await ref.watch(githubApiProvider).commits(key.repo, ref: key.ref, path: key.path, perPage: _perPage);
    return Paged(page.items, hasMore: page.hasNext);
  }

  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || !current.hasMore || current.loadingMore || current.loadMoreError != null) return;
    state = AsyncData(current.copyWith(loadingMore: true));
    try {
      final next = await ref
          .read(githubApiProvider)
          .commits(key.repo, ref: key.ref, path: key.path, page: current.page + 1, perPage: _perPage);
      if (!ref.mounted) return;
      state = AsyncData(Paged([...current.items, ...next.items], hasMore: next.hasNext, page: current.page + 1));
    } catch (e) {
      // Called fire-and-forget from scrolling: never throw, surface it instead.
      if (!ref.mounted) return;
      state = AsyncData(current.copyWith(loadingMore: false, loadMoreError: e));
    }
  }

  /// Clears a failed page so scrolling can try again.
  void retryLoadMore() {
    final current = state.value;
    if (current == null) return;
    state = AsyncData(current.copyWith());
    loadMore();
  }
}

typedef CommitKey = ({RepoRef repo, String sha});

final commitProvider = FutureProvider.autoDispose.family<GhCommit, CommitKey>(
  (ref, k) => ref.watch(githubApiProvider).commit(k.repo, k.sha),
);

typedef CompareKey = ({RepoRef repo, String base, String head});

final compareProvider = FutureProvider.autoDispose.family<GhCompare, CompareKey>(
  (ref, k) => ref.watch(githubApiProvider).compare(k.repo, k.base, k.head),
);

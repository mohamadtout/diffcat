import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/github/models/models.dart';
import '../auth/auth_controller.dart';

final repoProvider = FutureProvider.autoDispose.family<GhRepo, RepoRef>(
  (ref, r) => ref.watch(githubApiProvider).repo(r),
);

final branchesProvider = FutureProvider.autoDispose.family<List<GhBranch>, RepoRef>(
  (ref, r) => ref.watch(githubApiProvider).branches(r),
);

final tagsProvider = FutureProvider.autoDispose.family<List<GhBranch>, RepoRef>(
  (ref, r) => ref.watch(githubApiProvider).tags(r),
);

/// A page-accumulating list for infinite scroll.
class Paged<T> {
  const Paged(this.items, {required this.hasMore, this.page = 1, this.loadingMore = false, this.loadMoreError});

  final List<T> items;
  final bool hasMore;
  final int page;
  final bool loadingMore;

  /// Set when fetching the next page failed; the list shows a retry row.
  final Object? loadMoreError;

  Paged<T> copyWith({List<T>? items, bool? hasMore, int? page, bool? loadingMore, Object? loadMoreError}) => Paged(
    items ?? this.items,
    hasMore: hasMore ?? this.hasMore,
    page: page ?? this.page,
    loadingMore: loadingMore ?? this.loadingMore,
    loadMoreError: loadMoreError,
  );
}

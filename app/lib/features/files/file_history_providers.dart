import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/github/github_api.dart';
import '../../data/github/models/models.dart';
import '../auth/auth_controller.dart';
import 'history_graph.dart';

typedef FileHistoryKey = ({RepoRef repo, String path, String ref});

/// One branch's loaded history of the file.
class BranchHistory {
  const BranchHistory(this.name, {this.commits = const [], this.page = 0, this.hasMore = false, this.error});

  final String name;
  final List<GhCommit> commits;
  final int page;
  final bool hasMore;

  /// Why this branch couldn't be loaded (it's shown without commits).
  final Object? error;

  BranchLog get log => BranchLog(name, commits, complete: !hasMore || error != null);
}

class FileHistory {
  FileHistory(this.logs, {this.busy = false, this.loadMoreError});

  /// The branch the history was opened on, then the branches shown beside it.
  final List<BranchHistory> logs;

  /// Adding branches or loading older commits.
  final bool busy;
  final Object? loadMoreError;

  late final HistoryGraph graph = buildHistoryGraph([for (final l in logs) l.log]);

  List<String> get branches => [for (final l in logs.skip(1)) l.name];

  bool get hasMore => logs.any((l) => l.hasMore && l.error == null);

  FileHistory copyWith({List<BranchHistory>? logs, bool? busy, Object? loadMoreError}) =>
      FileHistory(logs ?? this.logs, busy: busy ?? this.busy, loadMoreError: loadMoreError);
}

/// A file's history on its branch plus other branches, for the history graph.
final fileHistoryProvider = AsyncNotifierProvider.autoDispose.family<FileHistoryNotifier, FileHistory, FileHistoryKey>(
  FileHistoryNotifier.new,
);

class FileHistoryNotifier extends AsyncNotifier<FileHistory> {
  FileHistoryNotifier(this.key);
  final FileHistoryKey key;

  static const perPage = 30;

  /// Branches beside the base. More lanes don't fit beside the text on a phone.
  static const maxBranches = 5;

  /// Branches of open pull requests shown without asking, when signed in
  /// (signed out, every branch costs part of a 60 requests/hour budget).
  static const autoBranches = 3;

  @override
  Future<FileHistory> build() async {
    final api = ref.watch(githubApiProvider);
    final signedIn = ref.watch(isSignedInProvider);
    // Started first, but awaited after the base: it never throws, so it can't
    // fail unobserved while the base loads.
    final pulls = signedIn ? _pullBranches(api) : Future.value(const <String>[]);
    final base = await _load(api, key.ref, 1);
    final others = await Future.wait((await pulls).map((b) => _loadOrError(api, b)));
    return FileHistory([base, ...others]);
  }

  /// Heads of open pull requests from this repo (not forks).
  Future<List<String>> _pullBranches(GitHubApi api) async {
    try {
      final pulls = (await api.pulls(key.repo)).items;
      return pulls
          .where((p) => p.headRepo?.toLowerCase() == key.repo.fullName.toLowerCase() && p.headRef != key.ref)
          .map((p) => p.headRef)
          .toSet()
          .take(autoBranches)
          .toList();
    } on Object {
      return const []; // nice to have; the base history still shows
    }
  }

  Future<BranchHistory> _load(GitHubApi api, String branch, int page, [BranchHistory? before]) async {
    final p = await api.commits(key.repo, ref: branch, path: key.path, page: page, perPage: perPage);
    return BranchHistory(branch, commits: [...?before?.commits, ...p.items], page: page, hasMore: p.hasNext);
  }

  Future<BranchHistory> _loadOrError(GitHubApi api, String branch) async {
    try {
      return await _load(api, branch, 1);
    } on Object catch (e) {
      return BranchHistory(branch, error: e);
    }
  }

  /// Shows [names] beside the base branch (already loaded ones are kept).
  Future<void> setBranches(List<String> names) async {
    final current = state.value;
    if (current == null || current.busy) return;
    final base = current.logs.first;
    final loaded = {for (final l in current.logs.skip(1)) l.name: l};
    final wanted = names.where((n) => n != base.name).toSet().take(maxBranches);
    state = AsyncData(current.copyWith(busy: true));
    final api = ref.read(githubApiProvider);
    final logs = await Future.wait([
      for (final n in wanted)
        if (loaded[n] case final l?) Future.value(l) else _loadOrError(api, n),
    ]);
    if (!ref.mounted) return;
    state = AsyncData(FileHistory([state.value?.logs.first ?? base, ...logs]));
  }

  /// Loads the next page of the branch whose loaded history ends soonest,
  /// since that's what hides older rows. Never throws (called from scrolling).
  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || current.busy || current.loadMoreError != null || !current.hasMore) return;
    final open = current.logs.where((l) => l.hasMore && l.error == null && l.commits.isNotEmpty).toList();
    if (open.isEmpty) return;
    final target = open.reduce((a, b) => a.commits.last.committedDate.isAfter(b.commits.last.committedDate) ? a : b);
    state = AsyncData(current.copyWith(busy: true));
    try {
      final next = await _load(ref.read(githubApiProvider), target.name, target.page + 1, target);
      if (!ref.mounted) return;
      final logs = state.value!.logs;
      state = AsyncData(FileHistory([for (final l in logs) l.name == target.name ? next : l]));
    } on Object catch (e) {
      if (!ref.mounted) return;
      state = AsyncData(state.value!.copyWith(busy: false, loadMoreError: e));
    }
  }

  void retryLoadMore() {
    final current = state.value;
    if (current == null) return;
    state = AsyncData(current.copyWith());
    loadMore();
  }
}

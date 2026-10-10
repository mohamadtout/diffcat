import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/github/github_exception.dart';
import '../../data/github/models/models.dart';
import '../auth/auth_controller.dart';
import '../offline/offline_providers.dart';

typedef PullListKey = ({RepoRef repo, String state});

/// Pull requests by state ('open', 'closed' or 'all'), recently updated first.
///
/// Offline, the downloaded list (if any) is joined by pull requests that were
/// downloaded one by one from their screen, so every saved PR can be found.
final pullListProvider = FutureProvider.autoDispose.family<List<GhPull>, PullListKey>((ref, k) async {
  final api = ref.watch(githubApiProvider);
  if (!ref.watch(isOfflineProvider(k.repo))) return (await api.pulls(k.repo, state: k.state)).items;
  final saved = ref.watch(savedRepoProvider(k.repo.fullName))?.pulls.keys.toList() ?? const <int>[];
  GitHubException? notListed;
  var listed = <GhPull>[];
  try {
    listed = (await api.pulls(k.repo, state: k.state)).items;
  } on GitHubException catch (e) {
    if (!e.notDownloaded) rethrow;
    notListed = e;
  }
  final known = {for (final p in listed) p.number};
  final extra = <GhPull>[];
  for (final n in saved.where((n) => !known.contains(n))) {
    try {
      final p = await api.pull(k.repo, n);
      if (matchesPullState(p.state, k.state)) extra.add(p);
    } on GitHubException catch (e) {
      if (!e.notDownloaded) rethrow;
    }
  }
  if (notListed != null && extra.isEmpty) throw notListed;
  return [...listed, ...extra]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
});

/// Whether a PR in [state] belongs under the list filter [filter].
bool matchesPullState(PullState state, String filter) => switch (filter) {
  'open' => state == PullState.open || state == PullState.draft,
  'closed' => state == PullState.closed || state == PullState.merged,
  _ => true,
};

typedef PullKey = ({RepoRef repo, int number});

final pullProvider = FutureProvider.autoDispose.family<GhPull, PullKey>(
  (ref, k) => ref.watch(githubApiProvider).pull(k.repo, k.number),
);

final pullFilesProvider = FutureProvider.autoDispose.family<List<GhFileChange>, PullKey>(
  (ref, k) => ref.watch(githubApiProvider).pullFiles(k.repo, k.number),
);

final pullCommitsProvider = FutureProvider.autoDispose.family<List<GhCommit>, PullKey>(
  (ref, k) => ref.watch(githubApiProvider).pullCommits(k.repo, k.number),
);

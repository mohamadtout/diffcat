import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/github/models/models.dart';
import '../auth/auth_controller.dart';

typedef PullListKey = ({RepoRef repo, String state});

final pullListProvider = FutureProvider.autoDispose.family<List<GhPull>, PullListKey>(
  (ref, k) async => (await ref.watch(githubApiProvider).pulls(k.repo, state: k.state)).items,
);

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

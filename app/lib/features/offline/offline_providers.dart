import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/storage.dart';
import '../../data/github/github_client.dart';
import '../../data/github/models/models.dart';
import '../auth/auth_controller.dart';
import 'downloader.dart';
import 'offline_store.dart';

/// Overridden in main() with the opened store. Null (tests, or no writable
/// storage) means no offline copies: the download UI hides itself.
final offlineStoreProvider = Provider<OfflineStore?>((ref) => null);

/// Bumps whenever something is downloaded or deleted. Watch it, then read the
/// store (saved repos are mutable, so watching them directly wouldn't rebuild).
final offlineRevisionProvider = NotifierProvider<OfflineRevision, int>(OfflineRevision.new);

class OfflineRevision extends Notifier<int> {
  @override
  int build() {
    final store = ref.watch(offlineStoreProvider);
    if (store != null) {
      void changed() => state++;
      store.addListener(changed);
      ref.onDispose(() => store.removeListener(changed));
    }
    return 0;
  }
}

/// The saved copy of [fullName], if any (rebuilds on changes).
final savedRepoProvider = Provider.family<SavedRepo?, String>((ref, fullName) {
  ref.watch(offlineRevisionProvider);
  return ref.watch(offlineStoreProvider)?.repo(fullName);
});

/// Repos the user switched to offline mode (lower-case `owner/name`):
/// only downloaded data is shown for them, the network is never used.
/// Remembered across launches.
final offlineModeProvider = NotifierProvider<OfflineMode, Set<String>>(OfflineMode.new);

class OfflineMode extends Notifier<Set<String>> {
  @override
  Set<String> build() => (ref.watch(sharedPrefsProvider).getStringList(StoreKeys.offlineModeRepos) ?? const []).toSet();

  void set(RepoRef repo, {required bool offline}) {
    final id = repo.fullName.toLowerCase();
    if (state.contains(id) == offline) return;
    state = offline ? {...state, id} : ({...state}..remove(id));
    ref.read(sharedPrefsProvider).setStringList(StoreKeys.offlineModeRepos, state.toList());
  }
}

/// Data saver: downloaded repos load from their saved copy, and only what
/// wasn't downloaded uses the network. Off (the default, "fresh"): lists,
/// branches and pull requests load live and saved copies are used for what
/// can't change (a commit's diff) or when GitHub can't be reached.
final dataSaverProvider = NotifierProvider<DataSaver, bool>(DataSaver.new);

class DataSaver extends Notifier<bool> {
  @override
  bool build() => ref.watch(sharedPrefsProvider).getBool(StoreKeys.dataSaver) ?? false;

  void set(bool on) {
    state = on;
    ref.read(sharedPrefsProvider).setBool(StoreKeys.dataSaver, on);
  }
}

/// Whether [repo]'s screens show its saved copy rather than live data:
/// offline mode, or data saver with a download.
final showsSavedCopyProvider = Provider.family<bool, RepoRef>(
  (ref, repo) =>
      ref.watch(isOfflineProvider(repo)) ||
      (ref.watch(dataSaverProvider) && ref.watch(savedRepoProvider(repo.fullName)) != null),
);

/// Whether [repo] is shown in offline mode right now (it must still be saved).
final isOfflineProvider = Provider.family<bool, RepoRef>(
  (ref, repo) =>
      ref.watch(offlineModeProvider).contains(repo.fullName.toLowerCase()) &&
      ref.watch(savedRepoProvider(repo.fullName)) != null,
);

/// Repo details of every download, read from the saved copies (works with no
/// network), newest first.
final savedReposInfoProvider = FutureProvider<List<GhRepo>>((ref) async {
  ref.watch(offlineRevisionProvider);
  final store = ref.watch(offlineStoreProvider);
  if (store == null) return const [];
  return [
    for (final saved in store.repos)
      await () async {
        final parts = saved.fullName.split('/');
        final info = await store.read(GitHubClient.cacheKey('/repos/${saved.fullName}'));
        if (info?.data case final Map<String, dynamic> json) return GhRepo.fromJson(json);
        return GhRepo(
          owner: parts.first,
          name: parts.last,
          defaultBranch: saved.branches.keys.firstOrNull ?? 'main',
          isPrivate: false,
        );
      }(),
  ];
});

typedef BranchTarget = ({RepoRef repo, String branch});

/// How many commits a branch has (for a full-history download). One request,
/// never saved.
final commitCountProvider = FutureProvider.autoDispose.family<int, BranchTarget>(
  (ref, t) => ref.watch(liveGithubApiProvider).commitCount(t.repo, t.branch),
);

/// What "All files" would store for a branch, from its file tree's sizes.
final filesEstimateProvider = FutureProvider.autoDispose.family<FilesEstimate, BranchTarget>(
  (ref, t) async => estimateTextFiles(await ref.watch(githubApiProvider).tree(t.repo, t.branch)),
);

String downloadKey(RepoRef repo, String branch) => '${repo.fullName.toLowerCase()}@$branch';

String pullDownloadKey(RepoRef repo, int number) => '${repo.fullName.toLowerCase()}#$number';

/// Running and failed downloads by [downloadKey] or [pullDownloadKey].
/// Finished ones drop out.
final downloadsProvider = NotifierProvider<DownloadsController, Map<String, DownloadProgress>>(DownloadsController.new);

class DownloadsController extends Notifier<Map<String, DownloadProgress>> {
  final _running = <String, void Function()>{}; // cancel, by key

  @override
  Map<String, DownloadProgress> build() => const {};

  /// Downloads (or updates) one branch. Returns the error message, if any.
  Future<String?> start(RepoRef repo, String branch, DownloadOptions options) async {
    final store = ref.read(offlineStoreProvider);
    final key = downloadKey(repo, branch);
    if (store == null || _running.containsKey(key)) return null;
    final downloader = BranchDownloader(
      store: store,
      repo: repo,
      branch: branch,
      options: options,
      token: ref.read(authTokenProvider).value,
      onProgress: (p) => state = {...state, key: p},
    );
    return _run(key, downloader.run, downloader.cancel);
  }

  /// Downloads (or updates) one pull request, open or closed.
  Future<String?> startPull(RepoRef repo, int number) async {
    final store = ref.read(offlineStoreProvider);
    final key = pullDownloadKey(repo, number);
    if (store == null || _running.containsKey(key)) return null;
    final downloader = PullDownloader(
      store: store,
      repo: repo,
      number: number,
      token: ref.read(authTokenProvider).value,
      onProgress: (p) => state = {...state, key: p},
    );
    return _run(key, downloader.run, downloader.cancel);
  }

  Future<String?> _run(String key, Future<void> Function() run, void Function() cancel) async {
    _running[key] = cancel;
    try {
      await run();
      state = {...state}..remove(key);
      return null;
    } on Object catch (e) {
      return e.toString(); // kept in state so the button can show it
    } finally {
      _running.remove(key);
      // Screens re-read, now from the fresh offline copy.
      ref.invalidate(githubApiProvider);
    }
  }

  /// Updates every saved branch of [repo] with its saved options.
  Future<String?> updateRepo(RepoRef repo) async {
    final saved = ref.read(offlineStoreProvider)?.repo(repo.fullName);
    for (final b in saved?.branches.entries.toList() ?? const <MapEntry<String, SavedBranch>>[]) {
      final error = await start(repo, b.key, b.value.options);
      if (error != null) return error;
    }
    return null;
  }

  void cancel(String key) => _running[key]?.call();

  void dismiss(String key) => state = {...state}..remove(key);
}

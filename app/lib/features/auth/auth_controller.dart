import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/storage.dart';
import '../../data/github/github_api.dart';
import '../../data/github/github_client.dart';
import '../../data/github/models/models.dart';
import '../offline/offline_providers.dart';
import '../offline/offline_store.dart';

/// Checks a token with GitHub and returns its user. Overridable in tests.
final tokenValidatorProvider = Provider<Future<GhUser> Function(String token)>(
  (ref) =>
      (token) => GitHubApi(GitHubClient(token: token)).viewer(),
);

/// The stored GitHub token, or null when signed out.
final authTokenProvider = AsyncNotifierProvider<AuthController, String?>(AuthController.new);

class AuthController extends AsyncNotifier<String?> {
  @override
  Future<String?> build() => ref.read(secureStoreProvider).read(StoreKeys.githubToken);

  /// Validates [token] against GitHub before persisting it.
  Future<GhUser> signIn(String token) async {
    final trimmed = token.trim();
    final user = await ref.read(tokenValidatorProvider)(trimmed);
    await ref.read(secureStoreProvider).write(StoreKeys.githubToken, trimmed);
    await ref.read(sharedPrefsProvider).setString(StoreKeys.viewerLogin, user.login);
    state = AsyncData(trimmed);
    unawaited(_clearPollEtags());
    return user;
  }

  /// Saved responses of the previous account must not outlive it.
  Future<void> _clearPollEtags() async {
    try {
      await (await pollEtagCache()).clear();
    } on Object {
      // No app storage (tests, unsupported platform): nothing was saved.
    }
  }

  Future<void> signOut() async {
    await ref.read(secureStoreProvider).delete(StoreKeys.githubToken);
    await ref.read(sharedPrefsProvider).remove(StoreKeys.viewerLogin); // poller's 'is this me?' cache
    unawaited(_clearPollEtags());
    state = const AsyncData(null);
  }
}

/// Transport for GitHub requests. Null: the real network. Tests (and the
/// store screenshots) swap in canned responses here, so everything above the
/// HTTP layer, offline copies included, runs as in the app.
final githubAdapterProvider = Provider<HttpClientAdapter?>((ref) => null);

Dio? _dio(Ref ref, String? token) {
  final adapter = ref.watch(githubAdapterProvider);
  return adapter == null ? null : (Dio(GitHubClient.baseOptions(token))..httpClientAdapter = adapter);
}

/// GitHub API, authenticated when signed in. Signing in is optional: public
/// repos work without a token (at GitHub's lower anonymous rate limit).
///
/// Downloads (features/offline): with data saver on, everything saved is
/// served from the device. Otherwise only what can't change (a commit's diff,
/// a file at a sha) is, and saved copies of the rest stand in when GitHub
/// can't be reached. Repos in offline mode ([offlineModeProvider]) never touch
/// the network.
final githubApiProvider = Provider<GitHubApi>((ref) {
  final store = ref.watch(offlineStoreProvider);
  final offline = ref.watch(offlineModeProvider);
  final dataSaver = ref.watch(dataSaverProvider);
  final token = ref.watch(authTokenProvider).value;
  return GitHubApi(
    GitHubClient(
      token: token,
      dio: _dio(ref, token),
      cache: store,
      preferSaved: dataSaver ? null : isImmutableKey,
      cacheOnly: store == null || offline.isEmpty
          ? null
          : (key) {
              final repo = OfflineStore.repoOfKey(key);
              return repo != null && offline.contains(repo) && store.repo(repo) != null;
            },
    ),
  );
});

/// Always asks GitHub, ignoring offline copies. The notification check uses
/// it, since a saved copy would hide new commits.
final liveGithubApiProvider = Provider<GitHubApi>((ref) {
  final token = ref.watch(authTokenProvider).value;
  return GitHubApi(GitHubClient(token: token, dio: _dio(ref, token)));
});

final isSignedInProvider = Provider<bool>((ref) => ref.watch(authTokenProvider).value != null);

/// The signed-in user, or null when signed out.
final viewerProvider = FutureProvider<GhUser?>(
  (ref) async => ref.watch(isSignedInProvider) ? ref.watch(githubApiProvider).viewer() : null,
);

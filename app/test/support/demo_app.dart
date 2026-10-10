import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:git_reviewer/app.dart';
import 'package:git_reviewer/core/storage/storage.dart';
import 'package:git_reviewer/data/github/github_api.dart';
import 'package:git_reviewer/data/github/github_client.dart';
import 'package:git_reviewer/data/github/response_cache.dart';
import 'package:git_reviewer/features/auth/auth_controller.dart';
import 'package:git_reviewer/features/auth/device_flow.dart';
import 'package:git_reviewer/features/auth/token_screen.dart';
import 'package:git_reviewer/features/notifications/local_notifications.dart';
import 'package:git_reviewer/features/offline/downloader.dart';
import 'package:git_reviewer/features/offline/offline_providers.dart';
import 'package:git_reviewer/features/offline/offline_store.dart';
import 'package:git_reviewer/features/terminal/ssh_host.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'demo_github.dart';

/// Demo SSH hosts (fictional addresses).
const demoHosts = [
  SshHost(
    id: 'demo-laptop',
    label: 'Dev laptop',
    host: 'dev-laptop.local',
    port: 22,
    username: 'demo',
    auth: SshAuth.key,
    startupCommand: 'cd ~/code/payments-api',
  ),
  SshHost(id: 'demo-build', label: 'Build server', host: '10.0.0.12', port: 2222, username: 'ci', auth: SshAuth.key),
];

/// The whole app ([GitReviewerApp]) running on [DemoGitHub]: real router,
/// providers and offline layer, with GitHub, secure storage and preferences
/// replaced by in-memory fakes. Nothing on the machine or device is touched.
class DemoEnv {
  DemoEnv._(this.prefs, this.github, this.store);

  final SharedPreferences prefs;
  final DemoGitHub github;
  final OfflineStore? store;

  /// [store]: offline copies (pass one seeded by [seedOfflineCopy] to show
  /// the Offline chip and Downloads screens). Null: offline storage off.
  static Future<DemoEnv> create({bool signedIn = true, OfflineStore? store, DemoGitHub? github}) async {
    FlutterSecureStorage.setMockInitialValues({if (signedIn) StoreKeys.githubToken: 'demo-token'});
    SharedPreferences.setMockInitialValues({
      StoreKeys.sshHosts: jsonEncode([for (final h in demoHosts) h.toJson()]),
      StoreKeys.pinnedRepos: ['${DemoGitHub.owner}/${DemoGitHub.repoName}'],
      StoreKeys.watchedRepos: ['${DemoGitHub.owner}/${DemoGitHub.repoName}'],
      StoreKeys.viewerLogin: DemoGitHub.owner,
      StoreKeys.recentRepos: ['${DemoGitHub.owner}/mobile-app'],
    });
    return DemoEnv._(await SharedPreferences.getInstance(), github ?? DemoGitHub(), store);
  }

  Widget app({LocalNotifications? notifications, Key? key}) => ProviderScope(
    key: key,
    overrides: [
      sharedPrefsProvider.overrideWithValue(prefs),
      localNotificationsProvider.overrideWithValue(notifications ?? LocalNotifications.disabled()),
      githubAdapterProvider.overrideWithValue(github),
      offlineStoreProvider.overrideWithValue(store),
      // Shows "Sign in with GitHub" as a build with a client ID would.
      deviceFlowProvider.overrideWithValue(() => DeviceFlow(clientId: 'demo')),
    ],
    child: const GitReviewerApp(),
  );
}

/// Saves the demo repo's main branch the way the Download button does, so the
/// Offline chip and Settings → Downloads have real entries and sizes.
Future<void> seedOfflineCopy(OfflineStore store, DemoGitHub github) => BranchDownloader(
  store: store,
  repo: DemoGitHub.repo,
  branch: 'main',
  options: const DownloadOptions(commits: 30, pulls: PullScope.open, files: false),
  onProgress: (_) {},
  api: GitHubApi(
    GitHubClient(
      dio: Dio(GitHubClient.baseOptions('demo-token'))..httpClientAdapter = github,
      cache: store,
      cacheMode: CacheMode.record,
    ),
  ),
).run();

/// Opens an offline store in a fresh folder [name] under [parent] (default:
/// the system temp folder, which apps on Android can't write to: pass
/// path_provider's getTemporaryDirectory() there).
Future<OfflineStore> tempOfflineStore(String name, {Directory? parent}) async {
  final dir = Directory('${(parent ?? Directory.systemTemp).path}/$name');
  if (dir.existsSync()) dir.deleteSync(recursive: true);
  return OfflineStore.open(dir);
}

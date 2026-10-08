import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:git_reviewer/app.dart';
import 'package:git_reviewer/core/layout/split_view.dart';
import 'package:git_reviewer/core/storage/storage.dart';
import 'package:git_reviewer/data/github/github_api.dart';
import 'package:git_reviewer/data/github/github_client.dart';
import 'package:git_reviewer/data/github/models/models.dart';
import 'package:git_reviewer/features/notifications/local_notifications.dart';
import 'package:git_reviewer/features/offline/downloader.dart';
import 'package:git_reviewer/features/offline/offline_providers.dart';
import 'package:git_reviewer/features/offline/offline_store.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Offline downloads against real GitHub (signed out) on a real device:
/// `make offline-test DEVICE=<id>`. Uses a tiny public repo and a throwaway
/// store, so the user's own downloads are untouched.
const _repo = (owner: 'octocat', name: 'Hello-World');

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late OfflineStore store;

  setUpAll(() async {
    dir = Directory('${(await getTemporaryDirectory()).path}/offline_device_test');
    if (await dir.exists()) await dir.delete(recursive: true);
    store = await OfflineStore.open(dir);
  });
  tearDownAll(() => dir.delete(recursive: true));

  testWidgets('download a public repo with all files, then read it with the network off', (tester) async {
    // Like the app: use the stored token if this device is signed in (5,000
    // requests/hour instead of 60 shared by everything on this network).
    final token = await tester.runAsync(() => const FlutterSecureStorage().read(key: StoreKeys.githubToken));
    debugPrint('Running ${token == null ? 'signed out' : 'signed in'}');
    // The first request on a cold network can be slow (DNS through a VPN, for
    // example), so allow a couple of attempts and log how long each took.
    final repo = await tester.runAsync(() async {
      for (var attempt = 1; ; attempt++) {
        final watch = Stopwatch()..start();
        try {
          final r = await GitHubApi(GitHubClient(token: token)).repo(_repo);
          debugPrint('GitHub reachable after ${watch.elapsedMilliseconds} ms (attempt $attempt)');
          return r;
        } on Object catch (e) {
          debugPrint('Attempt $attempt failed after ${watch.elapsedMilliseconds} ms: $e');
          if (attempt == 3) rethrow;
        }
      }
    });
    final branch = repo!.defaultBranch;
    DownloadProgress? last;
    await tester.runAsync(
      () => BranchDownloader(
        store: store,
        repo: _repo,
        branch: branch,
        options: const DownloadOptions(commits: 30, pulls: false, files: true),
        onProgress: (p) => last = p,
        token: token,
      ).run(),
    );
    expect(last?.error, isNull);
    final saved = store.repo(_repo.fullName)!;
    debugPrint('Saved ${saved.entries.length} responses, ${formatBytes(saved.bytes)}; branch $branch');
    expect(saved.branches[branch]!.commits, isNotEmpty);
    expect(saved.groupBytes(Groups.files(branch)), greaterThan(0), reason: 'tarball (via redirect) extracted');

    final offline = GitHubApi(
      GitHubClient(
        dio: Dio(BaseOptions(baseUrl: 'https://api.github.com'))..httpClientAdapter = _NoNetwork(),
        cache: store,
      ),
    );
    await tester.runAsync(() async {
      final commits = await offline.commits(_repo, ref: branch, perPage: BranchDownloader.pageSize);
      expect(commits.items, isNotEmpty);
      final detail = await offline.commit(_repo, commits.items.first.sha);
      expect(detail.sha, commits.items.first.sha);
      final tree = await offline.tree(_repo, branch);
      final readme = tree.entries.firstWhere((e) => e.path.toUpperCase().startsWith('README'));
      expect(await offline.fileContent(_repo, readme.path, branch), isNotEmpty);
    });
  });

  testWidgets('UI: saved label, update button, downloads screens, full-width diff', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPrefsProvider.overrideWithValue(prefs),
          localNotificationsProvider.overrideWithValue(LocalNotifications.disabled()),
          offlineStoreProvider.overrideWithValue(store),
        ],
        child: const GitReviewerApp(),
      ),
    );
    // Signed in: the download joins your repo list. Signed out: it gets a
    // "Downloaded" section. Either way its row is there, even if GitHub isn't.
    await _openFromHome(tester);
    await _waitFor(tester, find.byIcon(Icons.sync), what: 'update button for the saved branch');
    expect(find.textContaining('saved '), findsWidgets);
    await _screenshot(binding, tester, 'offline_01_repo_saved');

    final split = SplitView.isActive(tester.element(find.byType(Scaffold).last));
    final firstCommit = store.repo(_repo.fullName)!.branches.values.first.commits.first.title;
    await _waitFor(tester, find.text(firstCommit));
    await tester.tap(find.text(firstCommit).first);
    await _waitFor(tester, find.text('Changed since this'), what: 'commit detail');
    await _screenshot(binding, tester, 'offline_02_commit');
    if (split) {
      await tester.tap(find.byTooltip('Hide list (full-width view)'));
      await _settle(tester);
      await _screenshot(binding, tester, 'offline_03_full_width');
      await tester.tap(find.byTooltip('Show list'));
      await _settle(tester);
    } else {
      await tester.pageBack();
      await _settle(tester);
    }

    final before = store.repo(_repo.fullName)!.branches.values.first.updatedAt;
    await tester.tap(
      find.byWidgetPredicate((w) => w is IconButton && (w.tooltip?.startsWith('Update offline copy') ?? false)),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await _screenshot(binding, tester, 'offline_03b_updating');
    await _waitUntil(
      tester,
      () => store.repo(_repo.fullName)!.branches.values.first.updatedAt.isAfter(before),
      what: 'update to finish',
    );
    final ctx = tester.element(find.byType(Scaffold).last);
    expect(ProviderScope.containerOf(ctx).read(downloadsProvider), isEmpty, reason: 'update finished cleanly');

    await tester.tap(find.byType(BackButton).first);
    await _settle(tester);
    await _showRow(tester);
    await _screenshot(binding, tester, 'offline_04_home_downloaded');
    await tester.tap(find.descendant(of: _row(), matching: find.text('Offline')));
    await _waitFor(tester, find.text('Offline mode: showing only downloaded data'));
    await _waitFor(tester, find.text(firstCommit), what: 'commits from the saved copy');
    await _screenshot(binding, tester, 'offline_05_offline_mode');
    await tester.tap(find.text('Go online'));
    await _settle(tester);
    expect(find.text('Offline mode: showing only downloaded data'), findsNothing);
    await tester.tap(find.byType(BackButton).first);
    await _settle(tester);
    await tester.tap(find.text('Settings').last);
    await _waitFor(tester, find.text('Downloads'));
    await _screenshot(binding, tester, 'offline_06_settings');
    await tester.tap(find.text('Downloads'));
    await _waitFor(tester, find.text(_repo.fullName));
    await _screenshot(binding, tester, 'offline_07_downloads');
    await tester.tap(find.text(_repo.fullName));
    await _waitFor(tester, find.text('Branches'));
    await tester.tap(find.byType(ExpansionTile).first);
    await _settle(tester);
    await _screenshot(binding, tester, 'offline_08_repo_storage');
  });
}

Finder _row() => find.ancestor(of: find.text(_repo.name), matching: find.byType(ListTile)).first;

/// Brings the downloaded repo's row into view on the home screen.
Future<void> _showRow(WidgetTester tester) async {
  await _waitFor(tester, find.text('Repositories'));
  if (find.text('Filter repositories').evaluate().isNotEmpty) {
    await tester.enterText(find.byType(TextField).first, _repo.name); // signed in: filter your list
  }
  await _waitFor(tester, find.text(_repo.name), what: 'downloaded repo row');
  await tester.ensureVisible(_row());
  await _settle(tester);
}

Future<void> _openFromHome(WidgetTester tester) async {
  await _showRow(tester);
  await tester.tap(find.text(_repo.name).first);
}

class _NoNetwork implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? body, Future<void>? cancel) =>
      throw DioException.connectionError(requestOptions: o, reason: 'network disabled for this test');

  @override
  void close({bool force = false}) {}
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _waitUntil(WidgetTester tester, bool Function() done, {required String what}) async {
  final watch = Stopwatch()..start();
  while (!done()) {
    if (watch.elapsed > const Duration(seconds: 60)) fail('Timed out waiting for $what');
    await tester.pump(const Duration(milliseconds: 200));
  }
  await _settle(tester);
}

Future<void> _waitFor(WidgetTester tester, Finder finder, {String? what}) async {
  final watch = Stopwatch()..start();
  while (finder.evaluate().isEmpty) {
    if (watch.elapsed > const Duration(seconds: 60)) {
      final texts = find.byType(Text).evaluate().map((e) => (e.widget as Text).data).whereType<String>();
      fail('Timed out waiting for ${what ?? finder}. On screen: ${texts.take(25).join(' | ')}');
    }
    await tester.pump(const Duration(milliseconds: 200));
  }
  await _settle(tester);
}

bool _surfaceConverted = false;
Future<void> _screenshot(IntegrationTestWidgetsFlutterBinding binding, WidgetTester tester, String name) async {
  if (defaultTargetPlatform == TargetPlatform.android && !_surfaceConverted) {
    await binding.convertFlutterSurfaceToImage();
    _surfaceConverted = true;
    await tester.pump();
  }
  await binding.takeScreenshot(name);
}

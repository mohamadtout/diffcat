import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:git_reviewer/core/storage/storage.dart';
import 'package:git_reviewer/data/github/github_client.dart';
import 'package:git_reviewer/data/github/models/models.dart';
import 'package:git_reviewer/data/github/response_cache.dart';
import 'package:git_reviewer/features/offline/download_button.dart';
import 'package:git_reviewer/features/offline/downloader.dart';
import 'package:git_reviewer/features/offline/downloads_screen.dart';
import 'package:git_reviewer/features/offline/offline_providers.dart';
import 'package:git_reviewer/features/offline/offline_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _InstantDownloads extends DownloadsController {
  static DownloadOptions? last;

  @override
  Future<String?> start(RepoRef repo, String branch, DownloadOptions options) async {
    last = options;
    return null;
  }
}

void main() {
  late Directory dir;
  late OfflineStore store;
  const repo = (owner: 'o', name: 'r');

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('downloads_widget');
    store = await OfflineStore.open(dir);
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() => dir.delete(recursive: true));

  Future<void> pump(WidgetTester tester, Widget child, {List<Override> overrides = const []}) async {
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPrefsProvider.overrideWithValue(prefs),
          offlineStoreProvider.overrideWithValue(store),
          ...overrides,
        ],
        child: MaterialApp(home: child),
      ),
    );
    await tester.pump();
  }

  Future<void> saveMain() async {
    final sha = 'a' * 40;
    const path = '/repos/o/r/commits';
    final commitPath = '$path/$sha';
    await store.write(GitHubClient.cacheKey(commitPath), commitPath, null, CachedResponse(data: {'sha': sha}));
    store.saveBranch(
      'o/r',
      'main',
      SavedBranch(updatedAt: DateTime.now(), options: const DownloadOptions(), commits: [SavedCommit(sha, 'Fix bug')]),
    );
    await store.flush();
  }

  testWidgets('the download button turns into an update button once the branch is saved', (tester) async {
    await pump(
      tester,
      const Scaffold(
        body: DownloadButton(repo: repo, branch: 'main'),
      ),
    );
    expect(find.byTooltip('Download for offline'), findsOneWidget);

    await tester.runAsync(saveMain);
    await tester.pump();
    expect(find.byIcon(Icons.sync), findsOneWidget);
    expect(find.byTooltip('Download for offline'), findsNothing);
  });

  testWidgets('the download sheet offers diffs by default and full files as an option', (tester) async {
    await pump(
      tester,
      const Scaffold(
        body: DownloadButton(repo: repo, branch: 'main'),
      ),
    );
    await tester.tap(find.byTooltip('Download for offline'));
    await tester.pumpAndSettle();
    expect(find.text('Download for offline'), findsOneWidget);
    expect(
      tester.widget<SwitchListTile>(find.widgetWithText(SwitchListTile, 'All files')).value,
      isFalse,
      reason: 'diffs only by default',
    );
    expect(find.widgetWithText(FilledButton, 'Download'), findsOneWidget);
  });

  testWidgets('the sheet: a number, a starting commit or the whole history, and an estimate for all files', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(390, 1600) * 2
      ..devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await pump(
      tester,
      const Scaffold(
        body: DownloadButton(repo: repo, branch: 'main'),
      ),
      overrides: [
        downloadsProvider.overrideWith(_InstantDownloads.new),
        commitCountProvider.overrideWith((ref, _) async => 1234),
        filesEstimateProvider.overrideWith(
          (ref, _) async => const FilesEstimate(files: 3, bytes: 12000, truncated: false),
        ),
      ],
    );
    await tester.tap(find.byTooltip('Download for offline'));
    await tester.pumpAndSettle();
    FilledButton download() => tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Download'));

    await tester.enterText(find.widgetWithText(TextField, 'Number of commits'), '0');
    await tester.pump();
    expect(download().onPressed, isNull);
    await tester.enterText(find.widgetWithText(TextField, 'Number of commits'), '45');
    await tester.pump();
    expect(find.textContaining('About 52 GitHub requests'), findsOneWidget, reason: '4 + 2 list pages + 45 + 1');

    await tester.tap(find.text('Since…'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'From commit'), 'not-a-sha');
    await tester.pump();
    expect(find.text('A commit SHA: 7 to 40 hex characters'), findsOneWidget);
    expect(download().onPressed, isNull);
    await tester.enterText(find.widgetWithText(TextField, 'From commit'), 'abc1234');
    await tester.pump();
    expect(download().onPressed, isNotNull);

    await tester.tap(find.text('All'));
    await tester.pumpAndSettle();
    expect(find.text('main has 1,234 commits.'), findsOneWidget);
    expect(find.textContaining('About 1,281 GitHub requests'), findsOneWidget);

    await tester.tap(find.text('Open & closed'));
    await tester.tap(find.widgetWithText(SwitchListTile, 'All files'));
    await tester.pumpAndSettle();
    expect(find.textContaining('About 12 KB for 3 text files at main'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Download'));
    await tester.pump();
    final o = _InstantDownloads.last!;
    expect((o.range, o.pulls, o.files), (CommitRange.all, PullScope.openAndClosed, true));
  });

  testWidgets('downloads screens show sizes per repo, branch and commit', (tester) async {
    await tester.runAsync(saveMain);
    await pump(tester, const DownloadsScreen());
    expect(find.text('o/r'), findsOneWidget);
    expect(find.text(formatBytes(store.totalBytes)), findsWidgets);

    await pump(tester, const SavedRepoScreen(repo: repo));
    expect(find.text('main'), findsOneWidget);
    expect(find.textContaining('1/1 commits · diffs only'), findsOneWidget);
    await tester.tap(find.text('main'));
    await tester.pumpAndSettle();
    expect(find.text('Fix bug'), findsOneWidget);
    expect(find.byTooltip('Delete this commit'), findsOneWidget);
    expect(find.text('Delete branch'), findsOneWidget);
  });

  testWidgets('the "Updating…" message goes away when the update finishes', (tester) async {
    store.saveBranch(
      'o/r',
      'main',
      SavedBranch(updatedAt: DateTime.now(), options: const DownloadOptions(), commits: const []),
    );
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPrefsProvider.overrideWithValue(prefs),
          offlineStoreProvider.overrideWithValue(store),
          downloadsProvider.overrideWith(_InstantDownloads.new),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: DownloadButton(repo: repo, branch: 'main'),
          ),
        ),
      ),
    );
    await tester.tap(find.byIcon(Icons.sync));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Updating offline copy of main…'), findsNothing);
    expect(find.text('Offline copy of main updated'), findsOneWidget);
  });
}

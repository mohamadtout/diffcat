import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:git_reviewer/core/storage/storage.dart';
import 'package:git_reviewer/data/github/github_api.dart';
import 'package:git_reviewer/data/github/github_exception.dart';
import 'package:git_reviewer/data/github/models/models.dart';
import 'package:git_reviewer/features/auth/auth_controller.dart';
import 'package:git_reviewer/features/offline/offline_providers.dart';
import 'package:git_reviewer/features/offline/offline_store.dart';
import 'package:git_reviewer/features/repo/repo_screen.dart';
import 'package:git_reviewer/features/repos/repos_providers.dart';
import 'package:git_reviewer/features/repos/repos_screen.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockApi extends Mock implements GitHubApi {}

const _saved = GhRepo(owner: 'octocat', name: 'Hello-World', defaultBranch: 'master', isPrivate: false);
const _mine = GhRepo(owner: 'me', name: 'app', defaultBranch: 'main', isPrivate: true);

void main() {
  late Directory dir;
  late OfflineStore store;
  late SharedPreferences prefs;
  late ProviderContainer container;

  setUpAll(() => registerFallbackValue((owner: 'x', name: 'y')));
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('offline_mode');
    store = await OfflineStore.open(dir);
    // In memory only (no flush), so widget tests need no real file I/O.
    store.saveBranch(
      'octocat/Hello-World',
      'master',
      SavedBranch(updatedAt: DateTime.now(), options: const DownloadOptions(), commits: const []),
    );
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });
  tearDown(() => dir.delete(recursive: true));

  Future<void> pump(
    WidgetTester tester, {
    required bool signedIn,
    Future<List<GhRepo>> Function()? mine,
    String initial = '/repos',
  }) async {
    final api = _MockApi();
    when(() => api.repo(any())).thenAnswer((_) async => _saved);
    final router = GoRouter(
      initialLocation: initial,
      routes: [
        GoRoute(
          path: '/repos',
          builder: (_, _) => const ReposScreen(),
          routes: [
            GoRoute(
              path: ':owner/:name',
              builder: (_, s) => RepoScreen(repo: (owner: s.pathParameters['owner']!, name: s.pathParameters['name']!)),
            ),
          ],
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPrefsProvider.overrideWithValue(prefs),
          offlineStoreProvider.overrideWithValue(store),
          isSignedInProvider.overrideWithValue(signedIn),
          githubApiProvider.overrideWithValue(api),
          // Saved repo details come from disk normally; keep this test in memory.
          savedReposInfoProvider.overrideWith((ref) async => [_saved]),
          if (mine != null) myReposProvider.overrideWith((ref) => mine()),
        ],
        retry: (_, _) => null,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    container = ProviderScope.containerOf(tester.element(find.byType(Scaffold).first));
  }

  testWidgets('no internet: the repo list still shows downloads, and says why the rest are missing', (tester) async {
    await pump(tester, signedIn: true, mine: () async => throw GitHubException('Network error: offline'));
    expect(find.text("Can't reach GitHub"), findsOneWidget);
    expect(find.text('Hello-World'), findsOneWidget);
    expect(find.text('Offline'), findsOneWidget);
  });

  testWidgets('downloaded public repos join your own repos, once', (tester) async {
    await pump(tester, signedIn: true, mine: () async => [_mine, _saved]);
    expect(find.text('app'), findsOneWidget);
    expect(find.text('Hello-World'), findsOneWidget);
    expect(mergeRepos([_mine], [_saved, _mine]).map((r) => r.fullName), ['me/app', 'octocat/Hello-World']);
  });

  testWidgets('signed out, downloads have their own section', (tester) async {
    await pump(tester, signedIn: false);
    expect(find.text('Downloaded'), findsOneWidget);
    expect(find.text('Hello-World'), findsOneWidget);
  });

  testWidgets('the Offline chip opens offline; the row opens online; the repo screen switches both ways', (
    tester,
  ) async {
    await pump(tester, signedIn: false);
    await tester.tap(find.text('Offline'));
    await tester.pumpAndSettle();
    expect(container.read(offlineModeProvider), {'octocat/hello-world'});
    expect(find.text('Offline mode: showing only downloaded data'), findsOneWidget);

    await tester.tap(find.text('Go online'));
    await tester.pumpAndSettle();
    expect(container.read(offlineModeProvider), isEmpty);
    expect(find.text('Offline mode: showing only downloaded data'), findsNothing);

    await tester.tap(find.byTooltip('Go offline (downloaded data only)'));
    await tester.pumpAndSettle();
    expect(find.text('Offline mode: showing only downloaded data'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hello-World'));
    await tester.pumpAndSettle();
    expect(container.read(offlineModeProvider), isEmpty, reason: 'tapping the row opens online');
    expect(find.text('Offline mode: showing only downloaded data'), findsNothing);
  });

  test('offline mode is remembered and only applies to repos that are still downloaded', () async {
    final c = ProviderContainer(
      overrides: [sharedPrefsProvider.overrideWithValue(prefs), offlineStoreProvider.overrideWithValue(store)],
    );
    addTearDown(c.dispose);
    const saved = (owner: 'octocat', name: 'Hello-World');
    const notSaved = (owner: 'a', name: 'b');
    c.read(offlineModeProvider.notifier)
      ..set(saved, offline: true)
      ..set(notSaved, offline: true);
    expect(prefs.getStringList(StoreKeys.offlineModeRepos), containsAll(['octocat/hello-world', 'a/b']));
    expect(c.read(isOfflineProvider(saved)), isTrue);
    expect(c.read(isOfflineProvider(notSaved)), isFalse, reason: 'nothing downloaded to show');
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:git_reviewer/core/storage/storage.dart';
import 'package:git_reviewer/core/theme/app_theme.dart';
import 'package:git_reviewer/data/github/github_api.dart';
import 'package:git_reviewer/data/github/github_exception.dart';
import 'package:git_reviewer/data/github/models/models.dart';
import 'package:git_reviewer/features/auth/auth_controller.dart';
import 'package:git_reviewer/features/repo/repo_screen.dart';
import 'package:git_reviewer/features/repos/repos_screen.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockApi extends Mock implements GitHubApi {}

void main() {
  setUpAll(() => registerFallbackValue((owner: 'x', name: 'y')));

  // Regression: opening a repo by name used to crash with
  // "'_dependents.isEmpty': is not true" (controller disposed mid-animation),
  // and an inaccessible private repo should explain itself, not blow up.
  testWidgets('open-by-name to an inaccessible repo shows an explanation', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final api = _MockApi();
    when(() => api.repo(any())).thenThrow(GitHubException('Not Found', statusCode: 404));

    final router = GoRouter(
      initialLocation: '/repos',
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
          isSignedInProvider.overrideWithValue(true),
          githubApiProvider.overrideWithValue(api),
          myReposProvider.overrideWith((ref) async => <GhRepo>[]),
        ],
        retry: (_, _) => null,
        child: MaterialApp.router(theme: AppTheme.light(), routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Open by name'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'a-b/c-d');
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text("Can't open a-b/c-d"), findsOneWidget);
  });

  testWidgets('open-by-name rejects malformed input inline', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPrefsProvider.overrideWithValue(prefs),
          isSignedInProvider.overrideWithValue(true),
          myReposProvider.overrideWith((ref) async => <GhRepo>[]),
        ],
        child: const MaterialApp(home: ReposScreen()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Open by name'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'not a repo');
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Use owner/name or a github.com URL'), findsOneWidget);
  });

  group('signed out', () {
    Future<void> pumpHome(WidgetTester tester, GitHubApi api) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final router = GoRouter(
        initialLocation: '/repos',
        routes: [
          GoRoute(
            path: '/repos',
            builder: (_, _) => const ReposScreen(),
            routes: [
              GoRoute(
                path: ':owner/:name',
                builder: (_, s) =>
                    RepoScreen(repo: (owner: s.pathParameters['owner']!, name: s.pathParameters['name']!)),
              ),
            ],
          ),
          GoRoute(
            path: '/setup',
            builder: (_, _) => const Scaffold(body: Text('sign-in screen')),
          ),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPrefsProvider.overrideWithValue(prefs),
            isSignedInProvider.overrideWithValue(false),
            githubApiProvider.overrideWithValue(api),
          ],
          retry: (_, _) => null,
          child: MaterialApp.router(theme: AppTheme.light(), routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('opens a public repo by name and remembers it under Recent', (tester) async {
      final api = _MockApi();
      when(() => api.repo(any())).thenAnswer(
        (_) async => const GhRepo(owner: 'flutter', name: 'flutter', defaultBranch: 'main', isPrivate: false),
      );
      await pumpHome(tester, api);
      expect(find.text('Browse any public repo'), findsOneWidget);
      verifyNever(() => api.myRepos(page: any(named: 'page')));

      await tester.enterText(find.byType(TextField), 'https://github.com/flutter/flutter');
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('flutter'), findsWidgets); // repo screen title

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Recent'), findsOneWidget);
      expect(find.widgetWithText(ListTile, 'flutter/flutter'), findsOneWidget);
    });

    testWidgets('a repo that is not found suggests signing in', (tester) async {
      final api = _MockApi();
      when(() => api.repo(any())).thenThrow(GitHubException('Not Found', statusCode: 404));
      await pumpHome(tester, api);
      await tester.enterText(find.byType(TextField), 'someone/secret');
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Private repos need you to sign in'), findsOneWidget);
      expect(find.text('Recent'), findsNothing, reason: 'failed opens are not remembered');
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pumpAndSettle();
      expect(find.text('sign-in screen'), findsOneWidget);
    });
  });

  test('pushRecent moves to front, dedupes case-insensitively, caps length', () {
    expect(pushRecent(['a/b', 'c/d'], 'C/D'), ['C/D', 'a/b']);
    expect(pushRecent([for (var i = 0; i < 20; i++) 'o/$i'], 'new/one').length, 20);
    expect(pushRecent([for (var i = 0; i < 20; i++) 'o/$i'], 'new/one').last, 'o/18');
  });
}

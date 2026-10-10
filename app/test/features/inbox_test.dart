import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:git_reviewer/core/routing/app_router.dart';
import 'package:git_reviewer/core/routing/routes.dart';
import 'package:git_reviewer/core/storage/storage.dart';
import 'package:git_reviewer/data/github/github_api.dart';
import 'package:git_reviewer/data/github/github_client.dart';
import 'package:git_reviewer/data/github/github_exception.dart';
import 'package:git_reviewer/data/github/models/models.dart';
import 'package:git_reviewer/features/auth/auth_controller.dart';
import 'package:git_reviewer/features/inbox/inbox_screen.dart';
import 'package:git_reviewer/features/notifications/background.dart';
import 'package:git_reviewer/features/notifications/poll_state.dart';
import 'package:git_reviewer/features/notifications/poller.dart';
import 'package:git_reviewer/features/notifications/watch_controller.dart';
import 'package:git_reviewer/features/pulls/pull_screen.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/demo_app.dart';
import '../support/demo_github.dart';

class _MockApi extends Mock implements GitHubApi {}

GhSearchPull _p(String repo, int n) => GhSearchPull.fromJson({
  'number': n,
  'title': 'PR $n',
  'repository_url': 'https://api.github.com/repos/Acme/$repo',
  'user': {'login': 'bob'},
  'updated_at': '2026-10-09T10:00:00Z',
});

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (!tester.binding.hasScheduledFrame) return;
  }
}

void main() {
  test('search results know their repo and key', () {
    final p = _p('App', 7);
    expect(p.repo, (owner: 'Acme', name: 'App'));
    expect(p.key, 'acme/app#7');
  });

  test('review requests: the first check is a baseline, then only new ones notify', () {
    expect(reviewRequestEvents(null, [_p('app', 1)]), isEmpty);
    final events = reviewRequestEvents({'acme/app#1'}, [_p('app', 1), _p('app', 2)]);
    expect(events.single.route, Routes.pull((owner: 'Acme', name: 'app'), 2));
    expect(events.single.title, 'Review requested: app #2');
  });

  test('background checks run for watched repos or review requests while signed in', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    expect(backgroundChecksWanted(prefs), isFalse);
    await prefs.setBool(StoreKeys.notifyReviewRequests, true);
    expect(backgroundChecksWanted(prefs), isFalse, reason: 'signed out');
    await prefs.setString(StoreKeys.viewerLogin, 'me');
    expect(backgroundChecksWanted(prefs), isTrue);
    await prefs.setBool(StoreKeys.notifyReviewRequests, false);
    await prefs.setStringList(StoreKeys.watchedRepos, ['a/b']);
    expect(backgroundChecksWanted(prefs), isTrue);
  });

  GhNotification thread(String id, int pr, String reason, {String at = '2026-10-10T10:00:00Z', bool unread = true}) =>
      GhNotification.fromJson({
        'id': id,
        'reason': reason,
        'unread': unread,
        'updated_at': at,
        'repository': {'full_name': 'acme/app'},
        'subject': {'title': 'PR $pr', 'type': 'PullRequest', 'url': 'https://api.github.com/repos/acme/app/pulls/$pr'},
      });

  test('inbox: new and updated pull request threads notify once; read ones and issues are skipped', () {
    final first = inboxEvents(null, [thread('1', 7, 'review_requested')]);
    expect(first.events, isEmpty, reason: 'baseline');

    final issue = GhNotification.fromJson({
      'id': '9',
      'reason': 'mention',
      'unread': true,
      'updated_at': '2026-10-10T11:00:00Z',
      'repository': {'full_name': 'acme/app'},
      'subject': {'title': 'Bug', 'type': 'Issue', 'url': 'https://api.github.com/repos/acme/app/issues/3'},
    });
    final second = inboxEvents(first.seen, [
      thread('1', 7, 'review_requested'),
      thread('2', 8, 'mention'),
      thread('3', 9, 'comment', unread: false),
      issue,
    ]);
    expect(second.events.map((e) => (e.title, e.route, e.tag)), [
      ('Mentioned: app #8', Routes.pull((owner: 'acme', name: 'app'), 8), 'inbox:2'),
    ]);

    final third = inboxEvents(second.seen, [thread('1', 7, 'review_requested', at: '2026-10-10T12:00:00Z')]);
    expect(third.events.single.title, 'Review requested: app #7', reason: 'an update to a thread notifies again');
    expect(third.seen.keys, ['1'], reason: 'threads no longer unread are forgotten');
  });

  test('the poller reads the notifications inbox when turned on', () async {
    SharedPreferences.setMockInitialValues({StoreKeys.notifyReviewRequests: true, StoreKeys.viewerLogin: 'me'});
    final prefs = await SharedPreferences.getInstance();
    final api = _MockApi();
    when(() => api.client).thenReturn(GitHubClient(token: 't'));
    var threads = [thread('1', 1, 'review_requested')];
    when(api.notifications).thenAnswer((_) async => threads);
    final poller = Poller(api: api, prefs: prefs);
    expect((await poller.run()).events, isEmpty, reason: 'baseline');
    threads = [thread('1', 1, 'review_requested'), thread('2', 2, 'review_requested')];
    expect((await poller.run()).events.single.tag, 'inbox:2');
    expect((await poller.run()).events, isEmpty);
    verifyNever(() => api.searchPulls(any()));
  });

  test('fine-grained tokens can\'t read the inbox: review requests come from search', () async {
    SharedPreferences.setMockInitialValues({StoreKeys.notifyReviewRequests: true, StoreKeys.viewerLogin: 'me'});
    final prefs = await SharedPreferences.getInstance();
    final api = _MockApi();
    when(() => api.client).thenReturn(GitHubClient(token: 't'));
    when(api.notifications).thenThrow(GitHubException('Resource not accessible', statusCode: 403));
    var requested = [_p('app', 1)];
    when(() => api.searchPulls('review-requested:@me')).thenAnswer((_) async => GhSearchResult(requested, total: 1));
    final poller = Poller(api: api, prefs: prefs);
    expect((await poller.run()).events, isEmpty, reason: 'baseline');
    requested = [_p('app', 1), _p('app', 2)];
    expect((await poller.run()).events.single.tag, 'review:acme/app#2');
    expect((await poller.run()).events, isEmpty);
  });

  test('while the app is open, a tick checks only the inbox when the last full check is recent', () async {
    FlutterSecureStorage.setMockInitialValues({StoreKeys.githubToken: 't'});
    SharedPreferences.setMockInitialValues({
      StoreKeys.notifyReviewRequests: true,
      StoreKeys.viewerLogin: 'me',
      StoreKeys.lastPoll: '{"at":"${DateTime.now().toIso8601String()}","n":0,"c":0,"e":{}}',
    });
    final prefs = await SharedPreferences.getInstance();
    final api = _MockApi();
    when(() => api.client).thenReturn(GitHubClient(token: 't'));
    when(api.notifications).thenAnswer((_) async => [thread('1', 1, 'review_requested')]);
    final container = ProviderContainer(
      overrides: [sharedPrefsProvider.overrideWithValue(prefs), liveGithubApiProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);
    await container.read(authTokenProvider.future);

    await container.read(pollControllerProvider.notifier).foregroundTick();
    verify(api.notifications).called(1);
    verifyNever(() => api.searchPulls(any()));
    expect(prefs.getString(StoreKeys.inboxSeen), contains('"1"'), reason: 'baseline recorded');
  });

  testWidgets('the inbox lists review requests; a PR opens and back returns to the inbox', (tester) async {
    tester.view
      ..physicalSize = const Size(800, 1600)
      ..devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final env = await DemoEnv.create();
    await tester.pumpWidget(env.app());
    await _settle(tester);
    await tester.tap(find.text('Inbox'));
    await _settle(tester);
    expect(find.byType(InboxScreen), findsOneWidget);
    expect(find.text(DemoGitHub.openPullTitle), findsOneWidget);
    expect(find.text('Retry dead-letter queue on startup'), findsOneWidget);

    await tester.tap(find.text('Yours'));
    await _settle(tester);
    expect(find.text('Round zero-decimal currencies to whole units'), findsOneWidget);

    await tester.tap(find.text('Review requested'));
    await _settle(tester);
    await tester.tap(find.text(DemoGitHub.openPullTitle));
    await _settle(tester);
    expect(find.byType(PullScreen), findsOneWidget);

    await tester.pageBack();
    await _settle(tester);
    expect(find.byType(InboxScreen), findsOneWidget, reason: 'back returns to the inbox');
    expect(env.github.unknown, isEmpty);
    expect(
      ProviderScope.containerOf(tester.element(find.byType(MaterialApp))).read(routerProvider).state.uri.path,
      Routes.inbox,
    );
  });
}

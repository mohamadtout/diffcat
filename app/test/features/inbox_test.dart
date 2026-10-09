import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:git_reviewer/core/routing/app_router.dart';
import 'package:git_reviewer/core/routing/routes.dart';
import 'package:git_reviewer/core/storage/storage.dart';
import 'package:git_reviewer/data/github/github_api.dart';
import 'package:git_reviewer/data/github/github_client.dart';
import 'package:git_reviewer/data/github/models/models.dart';
import 'package:git_reviewer/features/inbox/inbox_screen.dart';
import 'package:git_reviewer/features/notifications/background.dart';
import 'package:git_reviewer/features/notifications/poll_state.dart';
import 'package:git_reviewer/features/notifications/poller.dart';
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

  test('the poller notifies new review requests when turned on', () async {
    SharedPreferences.setMockInitialValues({StoreKeys.notifyReviewRequests: true, StoreKeys.viewerLogin: 'me'});
    final prefs = await SharedPreferences.getInstance();
    final api = _MockApi();
    when(() => api.client).thenReturn(GitHubClient(token: 't'));
    var requested = [_p('app', 1)];
    when(() => api.searchPulls('review-requested:@me')).thenAnswer((_) async => GhSearchResult(requested, total: 1));
    final poller = Poller(api: api, prefs: prefs);
    expect((await poller.run()).events, isEmpty, reason: 'baseline');
    requested = [_p('app', 1), _p('app', 2)];
    expect((await poller.run()).events.single.tag, 'review:acme/app#2');
    expect((await poller.run()).events, isEmpty);
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

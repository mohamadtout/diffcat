import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:git_reviewer/core/routing/app_router.dart';
import 'package:git_reviewer/core/routing/routes.dart';
import 'package:git_reviewer/features/offline/offline_providers.dart';

import '../support/demo_app.dart';
import '../support/demo_github.dart';

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (!tester.binding.hasScheduledFrame) return;
  }
}

Future<DemoEnv> _openPull(WidgetTester tester, {bool signedIn = true}) async {
  tester.view
    ..physicalSize = const Size(900, 2000)
    ..devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  final env = await DemoEnv.create(signedIn: signedIn);
  await tester.pumpWidget(env.app());
  await _settle(tester);
  ProviderScope.containerOf(tester.element(find.byType(MaterialApp)))
      .read(routerProvider)
      .go(Routes.pull(DemoGitHub.repo, DemoGitHub.openPullNumber));
  await _settle(tester);
  return env;
}

void main() {
  testWidgets('existing threads show under their line', (tester) async {
    await _openPull(tester);
    expect(find.text('Should max be configurable per endpoint?'), findsOneWidget);
    expect(find.textContaining('One minute is the documented limit'), findsOneWidget);
  });

  testWidgets('comment on a line, then submit an approving review with it', (tester) async {
    final env = await _openPull(tester);
    expect(find.text('Tap a line to comment'), findsOneWidget);

    await tester.tap(find.textContaining('rand.Int63n').first);
    await _settle(tester);
    await tester.enterText(find.byType(TextField), 'Seed the random source?');
    await tester.tap(find.text('Add to review'));
    await _settle(tester);
    expect(find.text('Pending'), findsOneWidget);
    expect(find.text('1 pending comment'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Review'));
    await _settle(tester);
    await tester.enterText(find.byType(TextField), 'Nice work');
    await tester.tap(find.text('Approve'));
    await tester.tap(find.text('Submit review'));
    await _settle(tester);

    final (path, body) = env.github.posted.single;
    expect(path, '/repos/demo/payments-api/pulls/42/reviews');
    final review = body! as Map<String, dynamic>;
    expect(review['event'], 'APPROVE');
    expect(review['body'], 'Nice work');
    expect(review['commit_id'], DemoGitHub.sha(1));
    expect(review['comments'], [
      {'path': DemoGitHub.retryGo, 'line': 27, 'side': 'RIGHT', 'body': 'Seed the random source?'},
    ]);
    expect(find.text('Tap a line to comment'), findsOneWidget, reason: 'draft cleared');
  });

  testWidgets('signed out, the PR is read-only', (tester) async {
    await _openPull(tester, signedIn: false);
    expect(find.text('Tap a line to comment'), findsNothing);
  });

  testWidgets('offline, a downloaded PR reads fully, and reviewing waits for online mode', (tester) async {
    tester.view
      ..physicalSize = const Size(900, 2000)
      ..devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final github = DemoGitHub();
    final store = (await tester.runAsync(() => tempOfflineStore('review_offline')))!;
    await tester.runAsync(() => seedOfflineCopy(store, github));
    final env = await DemoEnv.create(store: store, github: github);
    await tester.pumpWidget(env.app());
    // Saved copies are real files: give their reads real time.
    Future<void> settleIo() async {
      for (var i = 0; i < 15; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    await settleIo();
    final container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
    container.read(offlineModeProvider.notifier).set(DemoGitHub.repo, offline: true);
    container.read(routerProvider).go(Routes.pull(DemoGitHub.repo, DemoGitHub.openPullNumber));
    await settleIo();

    expect(find.text('Offline: comments and reviews need online mode.'), findsOneWidget);
    expect(find.text('Tap a line to comment'), findsNothing);
    expect(find.byTooltip('Download #${DemoGitHub.openPullNumber} for offline'), findsNothing);
    expect(find.textContaining('Not downloaded'), findsNothing, reason: 'the PR and its threads were saved');
    expect(github.unknown, isEmpty);

    await tester.tap(find.text('Go online'));
    await settleIo();
    expect(find.text('Offline: comments and reviews need online mode.'), findsNothing);
    expect(find.byTooltip('Update the offline copy of #${DemoGitHub.openPullNumber}'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() => store.root.delete(recursive: true));
  });
}

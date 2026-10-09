import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:git_reviewer/core/routing/app_router.dart';
import 'package:git_reviewer/core/routing/routes.dart';
import 'package:git_reviewer/data/github/models/models.dart';
import 'package:git_reviewer/features/commits/commit_screen.dart';

import '../support/demo_app.dart';
import '../support/demo_github.dart';

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (!tester.binding.hasScheduledFrame) return;
  }
}

Future<void> _open(WidgetTester tester, {required bool signedIn}) async {
  tester.view
    ..physicalSize = const Size(900, 1800)
    ..devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  final env = await DemoEnv.create(signedIn: signedIn);
  await tester.pumpWidget(env.app());
  await _settle(tester);
  ProviderScope.containerOf(tester.element(find.byType(MaterialApp)))
      .read(routerProvider)
      .go(Routes.file(DemoGitHub.repo, DemoGitHub.retryGo, 'main', blame: true));
  await _settle(tester);
}

void main() {
  test('blame ranges map onto lines', () {
    BlameRange r(int s, int e) =>
        BlameRange(start: s, end: e, age: 1, sha: 's$s', title: '', authorName: 'a', date: DateTime(2026));
    final by = blameByLine([r(1, 2), r(3, 3)], 4);
    expect(by.map((b) => b?.sha), ['s1', 's1', 's3', null]);
  });

  testWidgets('blame shows who changed each range and opens its commit', (tester) async {
    await _open(tester, signedIn: true);
    expect(find.textContaining('lena-k'), findsNWidgets(2), reason: 'lines 1-9 and 10-16');
    expect(find.textContaining('priya-shah'), findsOneWidget);
    await tester.tap(find.textContaining('priya-shah'));
    await _settle(tester);
    final commit = tester.widget<CommitScreen>(find.byType(CommitScreen));
    expect(commit.sha, DemoGitHub.sha(102));
    expect(commit.focusPath, DemoGitHub.retryGo);
  });

  testWidgets('signed out, blame explains it needs a token', (tester) async {
    await _open(tester, signedIn: false);
    expect(find.textContaining('needs a token'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
  });
}

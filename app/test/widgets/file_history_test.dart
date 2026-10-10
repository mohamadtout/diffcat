import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:git_reviewer/core/routing/app_router.dart';
import 'package:git_reviewer/core/routing/routes.dart';
import 'package:git_reviewer/features/compare/compare_screen.dart';
import 'package:git_reviewer/features/files/history_graph_view.dart';

import '../support/demo_app.dart';
import '../support/demo_github.dart';
import '../support/settle.dart';

Future<DemoEnv> _open(WidgetTester tester, {bool signedIn = true}) async {
  tester.view
    ..physicalSize = const Size(800, 1600)
    ..devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  final env = await DemoEnv.create(signedIn: signedIn);
  await tester.pumpWidget(env.app());
  await settle(tester);
  ProviderScope.containerOf(tester.element(find.byType(MaterialApp)))
      .read(routerProvider)
      .go(Routes.history(DemoGitHub.repo, DemoGitHub.retryGo, 'main'));
  await settle(tester);
  return env;
}

void main() {
  testWidgets('signed in, open pull request branches are drawn beside the base', (tester) async {
    final env = await _open(tester);
    final legend = find.byType(GraphLegend);
    expect(find.descendant(of: legend, matching: find.text('main')), findsOneWidget);
    expect(find.descendant(of: legend, matching: find.text(DemoGitHub.featureBranch)), findsOneWidget);
    expect(find.descendant(of: legend, matching: find.text('fix/currency-rounding')), findsOneWidget);
    expect(find.textContaining('rebased from'), findsOneWidget);
    expect(find.textContaining('reverts'), findsOneWidget);
    expect(env.github.unknown, isEmpty);
  });

  testWidgets('compare mode diffs two picked versions of the file', (tester) async {
    await _open(tester);
    await tester.tap(find.byTooltip('Compare two versions'));
    await settle(tester);
    expect(find.text('Tap two versions to compare'), findsOneWidget);
    await tester.tap(find.text('Cap backoff at one minute'));
    await tester.tap(find.text('Retry on 409 Conflict'));
    await settle(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Compare'));
    await settle(tester);
    final compare = tester.widget<CompareScreen>(find.byType(CompareScreen));
    expect(compare.base, DemoGitHub.sha(103), reason: 'older version first');
    expect(compare.head, DemoGitHub.sha(111));
    expect(compare.focusPath, DemoGitHub.retryGo);
  });

  testWidgets('signed out shows only the base branch until branches are picked', (tester) async {
    await _open(tester, signedIn: false);
    final legend = find.byType(GraphLegend);
    expect(find.descendant(of: legend, matching: find.text(DemoGitHub.featureBranch)), findsNothing);

    await tester.tap(find.widgetWithText(ActionChip, 'Branches'));
    await settle(tester);
    await tester.tap(find.text(DemoGitHub.featureBranch));
    await tester.tap(find.widgetWithText(FilledButton, 'Show'));
    await settle(tester);
    expect(find.descendant(of: legend, matching: find.text(DemoGitHub.featureBranch)), findsOneWidget);
    expect(find.text('Cap backoff at one minute'), findsOneWidget);
  });
}

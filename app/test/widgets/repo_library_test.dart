import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:git_reviewer/core/routing/app_router.dart';
import 'package:git_reviewer/core/routing/routes.dart';
import 'package:git_reviewer/features/repos/repos_providers.dart';

import '../support/demo_app.dart';
import '../support/demo_github.dart';

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (!tester.binding.hasScheduledFrame) return;
  }
}

Finder _repoMenu(String name) => find.descendant(
  of: find.ancestor(of: find.text(name), matching: find.byType(ListTile)),
  matching: find.byTooltip('Repository options'),
);

void main() {
  testWidgets('select repos into a new folder, collapse it, hide a repo and find it in settings', (tester) async {
    tester.view
      ..physicalSize = const Size(800, 1800)
      ..devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final env = await DemoEnv.create();
    await tester.pumpWidget(env.app());
    await _settle(tester);
    final container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));

    // The demo pins payments-api, so the list has Pinned and Other.
    expect(find.text('Pinned'), findsOneWidget);
    expect(find.text('Other'), findsOneWidget);

    await tester.longPress(find.text('mobile-app'));
    await _settle(tester);
    await tester.tap(find.text('website'));
    await _settle(tester);
    expect(find.text('2 selected'), findsOneWidget);

    await tester.tap(find.byTooltip('Move to folder'));
    await _settle(tester);
    await tester.tap(find.text('New folder…'));
    await _settle(tester);
    await tester.enterText(find.byType(TextField).last, 'Client work');
    await tester.tap(find.text('Create'));
    await _settle(tester);
    expect(find.text('2 repos moved to Client work'), findsOneWidget);
    expect(find.text('2 selected'), findsNothing, reason: 'select mode ends after the action');
    expect(container.read(repoLibraryProvider).folderFor('demo/mobile-app')?.name, 'Client work');

    // Collapsing the folder hides its repos.
    await tester.tap(find.text('Client work'));
    await _settle(tester);
    expect(find.text('mobile-app'), findsNothing);
    expect(find.text('infra'), findsOneWidget);

    // Hide, undo, hide again.
    await tester.tap(_repoMenu('dotfiles'));
    await _settle(tester);
    await tester.tap(find.text('Hide').last);
    await _settle(tester);
    expect(find.text('dotfiles'), findsNothing);
    await tester.tap(find.text('Undo'));
    await _settle(tester);
    expect(find.text('dotfiles'), findsOneWidget);
    await tester.tap(_repoMenu('dotfiles'));
    await _settle(tester);
    await tester.tap(find.text('Hide').last);
    await _settle(tester);
    expect(find.text('dotfiles'), findsNothing);

    // The hide snackbar (with Undo) would cover the button below.
    ScaffoldMessenger.of(tester.element(find.byType(Scaffold).first)).clearSnackBars();
    container.read(routerProvider).go(Routes.repoList);
    await _settle(tester);
    expect(find.text('${DemoGitHub.owner}/dotfiles'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Unhide'));
    await _settle(tester);
    expect(container.read(repoLibraryProvider).hidden, isEmpty);
  });
}

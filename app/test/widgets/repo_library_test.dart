import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:git_reviewer/core/routing/app_router.dart';
import 'package:git_reviewer/core/routing/routes.dart';
import 'package:git_reviewer/features/repos/repo_library.dart';
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
    // The folder's menu sits at the row's end, in line with the repos' menus.
    expect(
      tester.getRect(find.byTooltip('Folder options')).right,
      moreOrLessEquals(tester.getRect(_repoMenu('infra')).right, epsilon: 16),
    );

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

  testWidgets('folders move up from their menu; the archive menu offers only what applies', (tester) async {
    tester.view
      ..physicalSize = const Size(800, 1800)
      ..devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final env = await DemoEnv.create();
    await tester.pumpWidget(env.app());
    await _settle(tester);
    final container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
    container.read(repoLibraryProvider.notifier)
      ..createFolder('First', folderColors[1])
      ..createFolder('Second', folderColors[2]);
    await _settle(tester);

    Future<List<String>> menuOf(Finder button) async {
      await tester.tap(button);
      await _settle(tester);
      return [
        for (final item in tester.widgetList<PopupMenuItem<String>>(find.byType(PopupMenuItem<String>))) item.value!,
      ];
    }

    Future<void> closeMenu() async {
      await tester.tapAt(const Offset(4, 4));
      await _settle(tester);
    }

    // The second folder moves up; the first one can only move down.
    expect(await menuOf(find.byTooltip('Folder options').at(1)), ['up', 'edit', 'delete']);
    await tester.tap(find.text('Move up'));
    await _settle(tester);
    expect(container.read(repoLibraryProvider).folders.map((f) => f.name), ['Second', 'First']);
    expect(await menuOf(find.byTooltip('Folder options').first), ['down', 'edit', 'delete']);
    await closeMenu();

    // Archive infra from its own menu; the snackbar goes away on its own.
    await tester.tap(_repoMenu('infra'));
    await _settle(tester);
    await tester.tap(find.text('Archive'));
    await _settle(tester);
    expect(find.text('infra archived'), findsOneWidget);
    await tester.pump(const Duration(seconds: 10));
    await _settle(tester);
    expect(find.text('infra archived'), findsNothing, reason: 'Undo snackbars time out');
    await tester.tap(find.text('Archived'));
    await _settle(tester);

    await tester.longPress(find.text('website'));
    await _settle(tester);
    expect(await menuOf(find.byTooltip('More')), ['archive', 'hide'], reason: 'nothing to unarchive');
    await closeMenu();
    await tester.tap(find.text('infra'));
    await _settle(tester);
    expect(await menuOf(find.byTooltip('More')), ['archive', 'unarchive', 'hide'], reason: 'a mix');
    await closeMenu();
    await tester.tap(find.text('website'));
    await _settle(tester);
    expect(await menuOf(find.byTooltip('More')), ['unarchive', 'hide'], reason: 'all archived');
    await tester.tap(find.text('Unarchive'));
    await _settle(tester);
    expect(find.text('infra unarchived'), findsOneWidget);
    expect(container.read(repoLibraryProvider).archived, isEmpty);
    expect(find.text('Archived'), findsNothing, reason: 'nothing left in it');
  });
}

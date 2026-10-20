import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:git_reviewer/core/layout/split_view.dart';
import 'package:git_reviewer/core/routing/app_router.dart';
import 'package:git_reviewer/core/routing/routes.dart';
import 'package:git_reviewer/core/storage/storage.dart';
import 'package:git_reviewer/features/pulls/pull_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/demo_app.dart';
import '../support/settle.dart';

Future<SharedPreferences> _pump(
  WidgetTester tester, {
  Widget? detail,
  Size size = const Size(1200, 800),
  Map<String, Object> prefs = const {},
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues(prefs);
  final store = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [sharedPrefsProvider.overrideWithValue(store)],
      child: MaterialApp(
        home: Scaffold(
          body: SplitView(master: const Text('LIST'), detail: detail),
        ),
      ),
    ),
  );
  return store;
}

void main() {
  testWidgets('wide screens can hide the list for a full-width detail, and remember it', (tester) async {
    final prefs = await _pump(tester, detail: const Text('DETAIL'));
    expect(find.text('LIST').hitTestable(), findsOneWidget);
    final detailWidth = tester.getSize(find.ancestor(of: find.text('DETAIL'), matching: find.byType(Expanded))).width;

    await tester.tap(find.byTooltip('Hide list (full-width view)'));
    await tester.pumpAndSettle();
    expect(find.text('LIST').hitTestable(), findsNothing);
    expect(find.text('LIST', skipOffstage: false), findsOneWidget, reason: 'list stays mounted (keeps scroll)');
    final fullWidth = tester.getSize(find.ancestor(of: find.text('DETAIL'), matching: find.byType(Expanded))).width;
    expect(fullWidth, greaterThan(detailWidth + 300));
    expect(prefs.getBool(StoreKeys.splitCollapsed), isTrue);

    await tester.tap(find.byTooltip('Show list'));
    await tester.pumpAndSettle();
    expect(find.text('LIST').hitTestable(), findsOneWidget);
  });

  testWidgets('with nothing selected the list always shows', (tester) async {
    await _pump(tester, prefs: {StoreKeys.splitCollapsed: true});
    expect(find.text('LIST').hitTestable(), findsOneWidget);
  });

  testWidgets('phones show only the list, no handle', (tester) async {
    await _pump(tester, detail: const Text('DETAIL'), size: const Size(400, 800));
    expect(find.text('DETAIL'), findsNothing);
    expect(find.byTooltip('Hide list (full-width view)'), findsNothing);
  });

  Future<void> openInbox(WidgetTester tester, {bool dataSaver = false}) async {
    tester.view
      ..physicalSize = const Size(1376, 1032) * 2
      ..devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final env = await DemoEnv.create();
    if (dataSaver) await env.prefs.setBool(StoreKeys.dataSaver, true);
    await tester.pumpWidget(env.app());
    await settle(tester);
    ProviderScope.containerOf(tester.element(find.byType(MaterialApp))).read(routerProvider).go(Routes.inbox);
    await settle(tester);
    await settle(tester);
  }

  testWidgets('tablets open the first item beside the list instead of an empty pane', (tester) async {
    await openInbox(tester);
    expect(find.text('Select a pull request'), findsNothing);
    expect(find.byType(PullView), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
  });

  testWidgets('not in data saver mode: each detail costs requests', (tester) async {
    await openInbox(tester, dataSaver: true);
    expect(find.text('Select a pull request'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
  });
}

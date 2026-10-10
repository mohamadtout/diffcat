import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:git_reviewer/core/routing/app_router.dart';
import 'package:git_reviewer/core/routing/routes.dart';

import '../support/demo_app.dart';
import '../support/demo_github.dart';
import '../support/settle.dart';

void main() {
  testWidgets('the keyboard on a landscape 7" tablet shrinks the screen, not the navigation rail', (tester) async {
    tester.view
      ..physicalSize = const Size(1920, 1200)
      ..devicePixelRatio = 2
      ..viewInsets = const FakeViewPadding(bottom: 600); // 300dp keyboard
    addTearDown(tester.view.reset);
    final env = await DemoEnv.create();
    await tester.pumpWidget(env.app());
    await settle(tester);
    final container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
    container.read(routerProvider).go(Routes.repo(DemoGitHub.repo, tab: 'console'));
    await settle(tester);

    expect(tester.takeException(), isNull, reason: 'no overflow');
    expect(tester.getSize(find.byType(NavigationRail)).height, greaterThan(500));
    // The console's input still sits above the keyboard.
    expect(tester.getRect(find.byType(TextField).last).bottom, lessThanOrEqualTo(600 - 300));
  });
}

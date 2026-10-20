import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:git_reviewer/core/routing/app_router.dart';
import 'package:git_reviewer/core/routing/routes.dart';
import 'package:git_reviewer/core/theme/app_theme.dart';
import 'package:git_reviewer/features/files/file_view_screen.dart';

import '../support/demo_app.dart';
import '../support/demo_github.dart';
import '../support/fonts.dart';
import '../support/settle.dart';

/// The diff is the core job: on a phone with large text, code shows on the
/// first screen of a commit, and code scales less than the UI around it.
void main() {
  setUpAll(loadSdkFonts);

  test('blame initials on narrow screens', () {
    expect(initials('Lena Kovač'), 'LK');
    expect(initials('lena-k'), 'LK');
    expect(initials('sam'), 'S');
    expect(initials(''), '?');
  });

  testWidgets('393×852 @1.5x: a commit shows diff lines on first load; code is clamped, the header is not', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(393, 852) * 2
      ..devicePixelRatio = 2;
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    final env = await DemoEnv.create();
    await tester.pumpWidget(env.app());
    await settle(tester);
    ProviderScope.containerOf(tester.element(find.byType(MaterialApp)))
        .read(routerProvider)
        .go(Routes.commit(DemoGitHub.repo, DemoGitHub.sha(1)));
    await settle(tester);

    final rows = find.byWidgetPredicate((w) => w.runtimeType.toString() == '_LineView');
    final onScreen = rows.evaluate().where((e) {
      final box = e.renderObject! as RenderBox;
      return box.hasSize && box.localToGlobal(Offset.zero).dy < 852 - 24;
    });
    expect(onScreen.length, greaterThanOrEqualTo(12), reason: 'diff lines visible without scrolling');

    double scale(Finder f) => MediaQuery.textScalerOf(tester.element(f)).scale(10) / 10;
    expect(scale(rows.first), AppTheme.codeMaxTextScale, reason: 'code clamps the system text size');
    expect(scale(find.text(DemoGitHub.latestCommitTitle)), 1.5, reason: 'the commit header keeps it');

    await tester.pumpWidget(const SizedBox());
    await settle(tester);
  });
}

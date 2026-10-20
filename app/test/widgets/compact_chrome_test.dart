import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:git_reviewer/core/routing/app_router.dart';
import 'package:git_reviewer/core/routing/routes.dart';

import '../support/demo_app.dart';
import '../support/demo_github.dart';
import '../support/fonts.dart';
import '../support/settle.dart';

/// Phones: the things that name a screen fit, and nothing clips with large
/// text. The screen-size sweep catches overflow errors; ellipsis and clipped
/// tabs aren't errors, so they're checked here.
void main() {
  setUpAll(loadSdkFonts);

  /// Whether [finder]'s text was cut short (ellipsis) where it's laid out.
  bool truncated(WidgetTester tester, Finder finder) {
    final text = tester.widget<Text>(finder);
    final box = tester.renderObject<RenderBox>(finder);
    final painter = TextPainter(
      text: TextSpan(text: text.data, style: DefaultTextStyle.of(tester.element(finder)).style.merge(text.style)),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      textScaler: MediaQuery.textScalerOf(tester.element(finder)),
    )..layout(maxWidth: box.size.width);
    return painter.didExceedMaxLines;
  }

  for (final (size, scale) in [(const Size(360, 640), 1.0), (const Size(393, 852), 1.5)]) {
    testWidgets('${size.width.toInt()}×${size.height.toInt()} @${scale}x: repo name, PR tabs, review choices', (
      tester,
    ) async {
      tester.view
        ..physicalSize = size * 2
        ..devicePixelRatio = 2;
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      final env = await DemoEnv.create();
      await tester.pumpWidget(env.app());
      await settle(tester);
      final router = ProviderScope.containerOf(tester.element(find.byType(MaterialApp))).read(routerProvider);

      router.go(Routes.repo(DemoGitHub.repo));
      await settle(tester);
      final title = find.descendant(of: find.byType(AppBar), matching: find.text(DemoGitHub.repoName));
      expect(title, findsOneWidget);
      expect(truncated(tester, title), isFalse, reason: 'repo name in the app bar');

      router.go(Routes.pull(DemoGitHub.repo, DemoGitHub.openPullNumber));
      await settle(tester);
      final commitsTab = find.textContaining('Commits (');
      await tester.ensureVisible(commitsTab);
      await tester.tap(commitsTab);
      await settle(tester);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Files (4)'));
      await settle(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Review'));
      await settle(tester);
      for (final choice in ['Comment', 'Approve', 'Request changes']) {
        expect(truncated(tester, find.text(choice)), isFalse, reason: '"$choice" fits on one line');
      }

      await tester.pumpWidget(const SizedBox());
      await settle(tester);
    });
  }
}

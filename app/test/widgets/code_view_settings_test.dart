import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:git_reviewer/core/routing/app_router.dart';
import 'package:git_reviewer/core/routing/routes.dart';
import 'package:git_reviewer/features/diff/diff_colors.dart';

import '../support/demo_app.dart';
import '../support/fonts.dart';

void main() {
  setUpAll(loadSdkFonts);

  testWidgets('diff color profiles: create, rename, delete; presets come back with Reset colors', (tester) async {
    // A phone with smaller system text: chip avatars shrink with the label,
    // which made the palette dots overflow. The palettes are below the fold,
    // where the screen-size test doesn't look.
    tester.view
      ..physicalSize = const Size(384, 823) * 2
      ..devicePixelRatio = 2;
    tester.platformDispatcher.textScaleFactorTestValue = 0.9;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    final env = await DemoEnv.create();
    await tester.pumpWidget(env.app());
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
    container.read(routerProvider).go(Routes.codeView);
    await tester.pumpAndSettle();
    DiffColorSettings colors() => container.read(diffColorsProvider);

    final list = find.ancestor(of: find.text('Font'), matching: find.byType(Scrollable)).first;
    await tester.scrollUntilVisible(find.text('New profile'), 200, scrollable: list);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'palette chips lay out at small text');

    // Delete a preset: it disappears until Reset colors.
    await tester.tap(find.widgetWithText(ChoiceChip, 'Neon'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete Neon'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ChoiceChip, 'Neon'), findsNothing);
    expect(colors().preset.id, 'github');

    // New profile from the colors shown.
    await tester.tap(find.text('New profile'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Night shift');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ChoiceChip, 'Night shift'), findsOneWidget);
    expect(colors().editingProfile, isTrue);
    expect(find.text('Your profile: color changes are saved to it.'), findsOneWidget);

    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Late');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ChoiceChip, 'Late'), findsOneWidget);

    // Reset colors: presets back, profile kept.
    await tester.tap(find.text('Reset colors'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ChoiceChip, 'Neon'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Late'), findsOneWidget);
    expect(colors().preset.id, 'github');

    // Deleting a profile asks first.
    await tester.tap(find.widgetWithText(ChoiceChip, 'Late'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete Late'));
    await tester.pumpAndSettle();
    expect(find.text('Delete Late?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ChoiceChip, 'Late'), findsNothing);
    expect(colors().profiles, isEmpty);
    expect(tester.takeException(), isNull);
  });
}

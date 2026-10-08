import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:git_reviewer/core/storage/storage.dart';
import 'package:git_reviewer/core/widgets/text_size_sheet.dart';
import 'package:git_reviewer/features/diff/diff_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('setFontSize clamps to bounds and persists', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(overrides: [sharedPrefsProvider.overrideWithValue(prefs)]);
    addTearDown(container.dispose);
    final notifier = container.read(diffSettingsProvider.notifier);

    expect(container.read(diffSettingsProvider).fontSize, DiffSettings.defaultFontSize);
    notifier.setFontSize(16);
    expect(container.read(diffSettingsProvider).fontSize, 16);
    expect(prefs.getDouble(StoreKeys.diffFontSize), 16);
    notifier.setFontSize(100);
    expect(container.read(diffSettingsProvider).fontSize, DiffSettings.maxFontSize);
    notifier.setFontSize(1);
    expect(container.read(diffSettingsProvider).fontSize, DiffSettings.minFontSize);
  });

  testWidgets('text size slider reports values while dragging', (tester) async {
    final values = <double>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: TextSizeSlider(value: 12, min: 8, max: 24, onChanged: values.add)),
      ),
    );
    expect(find.text('12'), findsOneWidget);

    await tester.drag(find.byType(Slider), const Offset(200, 0));
    await tester.pumpAndSettle();
    expect(values, isNotEmpty);
    expect(values.last, greaterThan(12));
    expect(values.every((v) => v * 2 == (v * 2).roundToDouble()), isTrue, reason: 'snaps to 0.5 steps');
  });
}

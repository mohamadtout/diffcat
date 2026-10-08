import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:git_reviewer/core/layout/readable_width.dart';

void main() {
  test('side padding centers the readable width, and is zero on phones', () {
    expect(ReadableWidth.sidesFor(390), EdgeInsets.zero);
    expect(ReadableWidth.sidesFor(720), EdgeInsets.zero);
    expect(ReadableWidth.sidesFor(1032), const EdgeInsets.symmetric(horizontal: 156));
    expect(ReadableWidth.sidesFor(1000, maxWidth: 600), const EdgeInsets.symmetric(horizontal: 200));
  });

  testWidgets('a wide list keeps rows at the readable width but scrolls from the margins', (tester) async {
    tester.view
      ..physicalSize = const Size(1200, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReadableWidth(
            builder: (sides) => ListView(
              padding: sides,
              children: [for (var i = 0; i < 50; i++) ListTile(title: Text('Row $i'))],
            ),
          ),
        ),
      ),
    );
    expect(tester.getSize(find.byType(ListTile).first).width, 720);
    await tester.dragFrom(const Offset(20, 600), const Offset(0, -300)); // in the left margin
    await tester.pumpAndSettle();
    expect(find.text('Row 0'), findsNothing);
  });
}

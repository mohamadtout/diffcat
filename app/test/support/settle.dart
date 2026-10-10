import 'package:flutter_test/flutter_test.dart';

/// Pumps until nothing is scheduled, for at most a second. pumpAndSettle can
/// spin forever on progress indicators.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (!tester.binding.hasScheduledFrame) return;
  }
}

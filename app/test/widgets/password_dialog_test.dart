import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:git_reviewer/features/terminal/host_edit_screen.dart';

void main() {
  // Regression: the controller was disposed while the dialog's exit animation
  // still rendered the field ("TextEditingController was used after being disposed").
  for (final submit in ['button', 'keyboard']) {
    testWidgets('password dialog returns the password and closes cleanly ($submit)', (tester) async {
      String? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async => result = await showDialog<String>(
                context: context,
                builder: (_) => const PasswordDialog(address: 'me@mac'),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 's3cret');
      if (submit == 'button') {
        await tester.tap(find.text('Install'));
      } else {
        await tester.testTextInput.receiveAction(TextInputAction.done);
      }
      await tester.pumpAndSettle(); // runs the exit animation
      expect(tester.takeException(), isNull);
      expect(result, 's3cret');
      expect(find.byType(PasswordDialog), findsNothing);
    });
  }
}

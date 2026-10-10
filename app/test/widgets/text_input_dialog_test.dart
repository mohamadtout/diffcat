import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:git_reviewer/core/widgets/text_input_dialog.dart';

import '../support/settle.dart';

void main() {
  testWidgets('askText ignores empty text, shows the validation error, and returns the text trimmed', (tester) async {
    String? result = 'not yet';
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => result = await askText(
              context,
              title: 'Hide an account',
              action: 'Hide',
              validate: (t) => t.contains(' ') ? 'No spaces' : null,
            ),
            child: const Text('ask'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('ask'));
    await settle(tester);

    await tester.enterText(find.byType(TextField), '   ');
    await tester.tap(find.text('Hide'));
    await settle(tester);
    expect(find.byType(AlertDialog), findsOneWidget, reason: 'empty: stays open');

    await tester.enterText(find.byType(TextField), 'two words');
    await tester.tap(find.text('Hide'));
    await settle(tester);
    expect(find.text('No spaces'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '  octo-org ');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);
    expect(find.byType(AlertDialog), findsNothing);
    expect(result, 'octo-org');

    await tester.tap(find.text('ask'));
    await settle(tester);
    await tester.tap(find.text('Cancel'));
    await settle(tester);
    expect(result, isNull);
  });
}

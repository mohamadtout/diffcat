import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:git_reviewer/core/theme/app_theme.dart';
import 'package:git_reviewer/features/terminal/host_key_dialog.dart';

void main() {
  test('fingerprints are split into groups of four after the hash name', () {
    expect(groupFingerprint('SHA256:abcdefghij'), 'SHA256: abcd efgh ij');
    expect(groupFingerprint('abcdefgh'), 'abcd efgh');
  });

  Future<bool?> open(WidgetTester tester, {String? previous}) async {
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => result = await confirmHostKey(
              context,
              hostName: 'dev-laptop.local',
              type: 'ssh-ed25519',
              fingerprint: 'SHA256:newnewnewnew',
              previous: previous,
            ),
            child: const Text('connect'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('connect'));
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('changed key: Cancel is the filled default and refuses; trusting is the quiet button', (tester) async {
    await open(tester, previous: 'SHA256:oldoldoldold');
    expect(find.text('Host key changed'), findsOneWidget);
    expect(find.text('SHA256: oldo ldol dold'), findsOneWidget);
    expect(find.text('SHA256: newn ewne wnew'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Cancel'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Trust new key'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Host key changed'), findsNothing);
  });

  testWidgets('changed key: Trust new key returns true', (tester) async {
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => result = await confirmHostKey(
              context,
              hostName: 'h',
              type: 'ssh-ed25519',
              fingerprint: 'SHA256:aaaa',
              previous: 'SHA256:bbbb',
            ),
            child: const Text('connect'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('connect'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Trust new key'));
    await tester.pumpAndSettle();
    expect(result, isTrue);
  });

  testWidgets('first connection: Trust is the filled button', (tester) async {
    await open(tester);
    expect(find.text('Trust this host?'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Trust'), findsOneWidget);
  });
}

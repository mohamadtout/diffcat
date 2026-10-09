import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:git_reviewer/features/notifications/local_notifications.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test/support/demo_app.dart';
import '../test/support/demo_github.dart';

/// Runs on a real phone/tablet: `make device-test DEVICE=<id>`.
///
/// Platform plugins (Keychain/Keystore, prefs, notifications) are real. GitHub
/// is replaced by the demo project (test/support/demo_github.dart) so no token
/// is needed, and screenshots of
/// each screen land in app/build/device_screenshots/.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('secure storage and preferences work on this device', (tester) async {
    const storage = FlutterSecureStorage();
    const key = 'device_test_probe';
    await storage.write(key: key, value: 'secret-value');
    expect(await storage.read(key: key), 'secret-value');
    await storage.delete(key: key);
    expect(await storage.read(key: key), isNull);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(key, 1.5);
    expect(prefs.getDouble(key), 1.5);
    await prefs.remove(key);
  });

  testWidgets('main screens render and navigate', (tester) async {
    // In-memory prefs and secure storage, so the run leaves nothing behind.
    final env = await DemoEnv.create();
    await tester.pumpWidget(env.app(notifications: await LocalNotifications.init()));
    await _settle(tester);
    final size = tester.view.physicalSize / tester.view.devicePixelRatio;
    debugPrint('Logical screen size: ${size.width.round()}×${size.height.round()}');

    Future<void> shot(String name) async {
      await _settle(tester);
      await _screenshot(binding, tester, name);
    }

    await shot('01_repos');

    await tester.tap(find.text(DemoGitHub.repoName).first);
    await shot('02_repo_commits');

    await tester.tap(find.text(DemoGitHub.latestCommitTitle).first);
    await shot('03_commit_diff');

    expect(await _openMenuItem(tester, 'Text size…'), isTrue, reason: 'diff menu has a Text size item');
    await _settle(tester);
    expect(find.byType(Slider), findsOneWidget);
    await tester.drag(find.byType(Slider), const Offset(180, 0));
    await shot('04_text_size_slider');
    await tester.tapAt(const Offset(20, 300)); // dismiss the sheet
    await _settle(tester);

    await _backTo(tester, find.text('Files'));
    await tester.tap(find.text('Files').last);
    await shot('05_files');
    await tester.tap(find.text('README.md').first);
    await shot('06_file_view');

    await _backTo(tester, find.text('PRs'));
    await tester.tap(find.text('PRs').last);
    await shot('07_pulls');
    await tester.tap(find.text(DemoGitHub.openPullTitle).first);
    await shot('08_pull_detail');

    await _backTo(tester, find.text('Settings'));
    await tester.tap(find.text('Settings').last);
    await shot('09_settings');
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      expect(find.textContaining('Android'), findsNothing, reason: 'no Android-only advice on iOS');
    }
    await tester.tap(find.text('Terminal').last);
    await shot('10_terminal');
    await tester.tap(find.text('Inbox').last);
    await shot('11_inbox');

    expect(env.github.unknown, isEmpty, reason: 'unexpected GitHub calls: ${env.github.unknown}');
    expect(tester.takeException(), isNull);
  });
}

/// pumpAndSettle can spin forever on progress indicators; cap the wait.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 40; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (!tester.binding.hasScheduledFrame) return;
  }
}

/// Pops pushed routes (phone layout) until [target] is visible. On wide screens
/// the detail sits beside the list, so usually nothing is popped.
Future<void> _backTo(WidgetTester tester, Finder target) async {
  while (target.evaluate().isEmpty && find.byType(BackButton).evaluate().isNotEmpty) {
    await tester.tap(find.byType(BackButton).first);
    await _settle(tester);
  }
}

/// Opens each popup menu on screen until one contains [label], then taps it.
Future<bool> _openMenuItem(WidgetTester tester, String label) async {
  final menus = find.byType(PopupMenuButton<String>);
  for (var i = menus.evaluate().length - 1; i >= 0; i--) {
    await tester.tap(menus.at(i));
    await _settle(tester);
    if (find.text(label).evaluate().isNotEmpty) {
      await tester.tap(find.text(label));
      return true;
    }
    await tester.tapAt(const Offset(5, 5));
    await _settle(tester);
  }
  return false;
}

/// Screenshots work on Android only after the surface is converted, which must
/// happen after the app has rendered, so it's done lazily on the first shot.
bool _surfaceConverted = false;
Future<void> _screenshot(IntegrationTestWidgetsFlutterBinding binding, WidgetTester tester, String name) async {
  if (defaultTargetPlatform == TargetPlatform.android && !_surfaceConverted) {
    await binding.convertFlutterSurfaceToImage();
    _surfaceConverted = true;
    await tester.pump();
  }
  await binding.takeScreenshot(name);
}

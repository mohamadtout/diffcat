import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:git_reviewer/core/routing/app_router.dart';
import 'package:git_reviewer/core/routing/routes.dart';
import 'package:git_reviewer/core/storage/storage.dart';
import 'package:git_reviewer/features/notifications/local_notifications.dart';
import 'package:git_reviewer/features/settings/settings_screen.dart';
import 'package:git_reviewer/features/terminal/ssh_session.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

import '../test/support/demo_app.dart';
import '../test/support/demo_github.dart';

/// Store screenshots on demo data: `make store-screenshots` runs this on each
/// simulator/emulator size. Every screen is the real app; GitHub, the SSH
/// host and storage are fakes (test/support/), so no account is involved.
///
/// Raw shots land in `app/build/store/raw/<device>/`; `tool/store/frame_test.dart`
/// adds the marketing captions.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('store screenshots', (tester) async {
    final github = DemoGitHub();
    final store = await tester.runAsync(() async {
      final s = await tempOfflineStore('store_screenshots', parent: await getTemporaryDirectory());
      await seedOfflineCopy(s, github);
      return s;
    });
    final env = await DemoEnv.create(store: store, github: github);
    await env.prefs.setBool(StoreKeys.diffWrap, true); // whole lines, no sideways scrolling
    // Real notifications plugin, so Settings shows what users see.
    await tester.pumpWidget(env.app(notifications: await LocalNotifications.init()));
    await _settle(tester);

    final container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
    final router = container.read(routerProvider);
    final size = tester.view.physicalSize / tester.view.devicePixelRatio;
    // List and detail side by side (SplitView) from 840dp; phones and narrow
    // tablets push the detail instead.
    final split = size.width >= 840;
    debugPrint('Logical size ${size.width.round()}×${size.height.round()} (${split ? 'split view' : 'single pane'})');

    Future<void> go(String location) async {
      router.go(location);
      await _settle(tester, frames: 30);
    }

    Future<void> shot(String name) async {
      // No keyboard: it isn't in the screenshot, only the space it takes.
      FocusManager.instance.primaryFocus?.unfocus();
      await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
      await _settle(tester);
      await _screenshot(binding, tester, name);
    }

    container.read(themeModeProvider.notifier).set(ThemeMode.light);
    await go(Routes.repos);
    await shot('01_repos');

    // Commits, then a commit's diff: beside the list when split, else pushed.
    await go(Routes.repo(DemoGitHub.repo));
    if (!split) await shot('02_commits');
    await tester.tap(find.text(DemoGitHub.latestCommitTitle).first);
    await _settle(tester, frames: 30);
    await shot(split ? '02_commit_split' : '03_diff');
    if (split) {
      await tester.tap(find.byTooltip('Hide list (full-width view)'));
      await shot('03_diff_full_width');
      await tester.tap(find.byTooltip('Show list'));
      await _settle(tester);
    }

    await go(Routes.repo(DemoGitHub.repo, tab: 'pulls'));
    await tester.tap(find.text(DemoGitHub.openPullTitle).first);
    await _settle(tester, frames: 30);
    await shot('04_pull');

    if (split) {
      await go(Routes.repo(DemoGitHub.repo, tab: 'files'));
      for (final part in DemoGitHub.retryGo.split('/')) {
        await tester.tap(find.text(part).first);
        await _settle(tester, frames: 20);
      }
    } else {
      await go(Routes.file(DemoGitHub.repo, DemoGitHub.retryGo, 'main'));
    }
    await shot('05_file');

    await go(Routes.changedSince(DemoGitHub.repo, ref: 'main', base: 'v1.4.0'));
    await shot('06_changed_since');

    // Offline: the saved copy in offline mode, and its storage breakdown.
    await go(Routes.repos);
    await tester.tap(find.text('Offline').first);
    await _settle(tester, frames: 30);
    if (split) {
      // A saved commit beside the list, rather than an empty detail pane.
      await tester.tap(find.text(DemoGitHub.latestCommitTitle).first);
      await _settle(tester, frames: 30);
    }
    await shot('07_offline_mode');
    await tester.tap(find.text('Go online'));
    await _settle(tester);
    await go(Routes.savedRepo(DemoGitHub.repo));
    await tester.tap(find.byType(ExpansionTile).first);
    await shot('08_downloads');

    // Terminal: a session to the demo host, with typical output written in
    // (no real SSH connection).
    final host = demoHosts.first;
    final session = container.read(sshSessionsProvider).obtain(host)..status = SshStatus.connected;
    await go(Routes.terminalSession(host.id));
    session.terminal.write(_terminalDemo);
    await shot('09_terminal');

    await go(Routes.repo(DemoGitHub.repo, tab: 'console'));
    await tester.enterText(find.byType(TextField).last, 'log -n 5');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await _settle(tester, frames: 30);
    await shot('10_console');

    container.read(themeModeProvider.notifier).set(ThemeMode.dark);
    await go(Routes.commit(DemoGitHub.repo, DemoGitHub.sha(1)));
    await shot('11_diff_dark');
    container.read(themeModeProvider.notifier).set(ThemeMode.light);
    await go(Routes.settings);
    await shot('12_settings');

    expect(github.unknown, isEmpty, reason: 'GitHub calls the demo does not cover');
  });
}

const _p = '\x1b[1;32mpayments-api\x1b[0m \x1b[1;34m%\x1b[0m ';
const _terminalDemo =
    '${_p}git status -sb\r\n'
    '\x1b[32m## feature/retry-backoff\x1b[0m [ahead \x1b[32m1\x1b[0m]\r\n'
    ' \x1b[31mM\x1b[0m internal/webhooks/retry.go\r\n'
    '\x1b[31m??\x1b[0m internal/webhooks/retry_test.go\r\n'
    '${_p}go test ./internal/webhooks\r\n'
    '\x1b[32mok\x1b[0m  internal/webhooks  0.412s\r\n'
    '${_p}git log --oneline --graph\r\n'
    '* \x1b[33m3f9a1c2\x1b[0m Add exponential backoff\r\n'
    '* \x1b[33m8b07d44\x1b[0m Fix rounding of JPY amounts\r\n'
    '*   \x1b[33mc41e9aa\x1b[0m Merge pull request #39\r\n'
    '\x1b[31m|\x1b[0m\x1b[32m\\\x1b[0m\r\n'
    '\x1b[31m|\x1b[0m * \x1b[33m5d2e310\x1b[0m Reconcile ledger\r\n'
    '\x1b[31m|\x1b[0m\x1b[32m/\x1b[0m\r\n'
    '* \x1b[33m77a0b1e\x1b[0m (\x1b[1;33mtag: v1.4.0\x1b[0m) Validate keys\r\n'
    '${_p}git push\r\n'
    'To github.com:demo/payments-api.git\r\n'
    '   8b07d44..3f9a1c2  feature/retry-backoff\r\n'
    '$_p';

/// pumpAndSettle can spin forever on progress indicators; cap the wait.
Future<void> _settle(WidgetTester tester, {int frames = 10}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
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

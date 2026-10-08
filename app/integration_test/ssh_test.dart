import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:git_reviewer/app.dart';
import 'package:git_reviewer/core/storage/storage.dart';
import 'package:git_reviewer/features/notifications/local_notifications.dart';
import 'package:git_reviewer/features/terminal/ssh_host.dart';
import 'package:git_reviewer/features/terminal/ssh_session.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Real SSH from the device to a real host: `make ssh-test` (see docs/conventions.md).
///
/// Needs dart-defines: SSH_HOST, SSH_USER, SSH_KEY_B64 (base64 OpenSSH private
/// key already in the host's authorized_keys) and SSH_FP (`ssh-keygen -lf` of
/// the host key). Skipped when SSH_HOST is empty.
const _host = String.fromEnvironment('SSH_HOST');
const _user = String.fromEnvironment('SSH_USER');
const _keyB64 = String.fromEnvironment('SSH_KEY_B64');
const _fingerprint = String.fromEnvironment('SSH_FP');
const _hostId = 'device-test-host';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final privateKey = _keyB64.isEmpty ? '' : utf8.decode(base64.decode(_keyB64));
  const host = SshHost(id: _hostId, label: 'Test host', host: _host, port: 22, username: _user, auth: SshAuth.key);

  tearDownAll(() => const FlutterSecureStorage().delete(key: StoreKeys.sshPrivateKey(_hostId)));

  testWidgets('terminal: trust host key, run commands on the host', (tester) async {
    SharedPreferences.setMockInitialValues({
      StoreKeys.sshHosts: jsonEncode([host.toJson()]),
    });
    final prefs = await SharedPreferences.getInstance();
    await const FlutterSecureStorage().write(key: StoreKeys.sshPrivateKey(_hostId), value: privateKey);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPrefsProvider.overrideWithValue(prefs),
          localNotificationsProvider.overrideWithValue(LocalNotifications.disabled()),
        ],
        child: const GitReviewerApp(),
      ),
    );
    await _waitFor(tester, () => find.text('Terminal').evaluate().isNotEmpty);
    await tester.tap(find.text('Terminal').last);
    await _waitFor(tester, () => find.text('Test host').evaluate().isNotEmpty);
    await tester.tap(find.text('Test host'));

    await _waitFor(tester, () => find.text('Trust this host?').evaluate().isNotEmpty, what: 'host key prompt');
    expect(find.textContaining(_fingerprint), findsOneWidget, reason: 'app shows the same fingerprint as ssh-keygen');
    await _screenshot(binding, tester, 'ssh_01_trust_prompt');
    await tester.tap(find.text('Trust'));

    final context = tester.element(find.byType(Scaffold).last);
    final session = ProviderScope.containerOf(context).read(sshSessionsProvider).existing(_hostId)!;
    await _waitFor(tester, () => session.status == SshStatus.connected, what: 'connected (${session.error})');
    // The shell computes 6*7, so 42 only appears if the command really ran on the host.
    session.sendKeys(r'clear; echo "GR_$((6*7))_OK $(whoami)@$(hostname)"; git --version<enter>');
    await _waitFor(tester, () => _screen(session).contains('GR_42_OK'), what: 'command output');
    expect(_screen(session), contains('GR_42_OK $_user@'));
    expect(_screen(session), contains('git version'));
    await _screenshot(binding, tester, 'ssh_02_shell');

    // Remembered: reconnecting must not prompt again.
    session.disconnect();
    await session.connect();
    await _waitFor(tester, () => session.status == SshStatus.connected, what: 'reconnected');
    expect(find.text('Trust this host?'), findsNothing);
    session.disconnect();
  });

  testWidgets('install a new device key with an existing login, then log in with it', (tester) async {
    final fresh = generateEd25519('git-reviewer-device-test-installed');
    final admin = await openSshClient(
      host,
      identities: SSHKeyPair.fromPem(privateKey),
      onVerifyHostKey: (_, _) => true,
    );
    try {
      await installPublicKey(admin, fresh.publicLine);
      await installPublicKey(admin, fresh.publicLine); // idempotent
      final count = utf8.decode(await admin.run("grep -cxF '${fresh.publicLine}' ~/.ssh/authorized_keys"));
      expect(count.trim(), '1', reason: 'installed exactly once');
    } finally {
      await admin.close();
    }

    final client = await openSshClient(
      host,
      identities: SSHKeyPair.fromPem(fresh.privatePem),
      onVerifyHostKey: (_, _) => true,
    );
    try {
      expect(utf8.decode(await client.run('echo logged-in-with-new-key')).trim(), 'logged-in-with-new-key');
    } finally {
      await client.close();
    }
  });
}

String _screen(SshSessionController s) => s.terminal.buffer.getText();

Future<void> _waitFor(
  WidgetTester tester,
  bool Function() done, {
  String what = 'condition',
  Duration timeout = const Duration(seconds: 30),
}) async {
  final watch = Stopwatch()..start();
  while (!done()) {
    if (watch.elapsed > timeout) {
      final texts = find.byType(Text).evaluate().map((e) => (e.widget as Text).data).whereType<String>();
      fail('Timed out waiting for $what. On screen: ${texts.take(20).join(' | ')}');
    }
    await tester.pump(const Duration(milliseconds: 200));
  }
  await tester.pump(const Duration(milliseconds: 300));
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

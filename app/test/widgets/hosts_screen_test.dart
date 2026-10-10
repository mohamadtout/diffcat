import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:git_reviewer/core/storage/storage.dart';
import 'package:git_reviewer/features/terminal/hosts_screen.dart';
import 'package:git_reviewer/features/terminal/ssh_host.dart';
import 'package:git_reviewer/features/terminal/ssh_session.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('the host icon turns green when its session connects, without leaving the list', (tester) async {
    const host = SshHost(id: 'h1', label: 'Laptop', host: 'laptop.local', port: 22, username: 'me', auth: SshAuth.key);
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await prefs.writeJsonList(StoreKeys.sshHosts, [host.toJson()]);
    final container = ProviderContainer(overrides: [sharedPrefsProvider.overrideWithValue(prefs)]);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: HostsScreen()),
      ),
    );
    Color? iconColor() => tester.widget<Icon>(find.byIcon(Icons.dns_outlined)).color;
    expect(iconColor(), isNull);

    // The terminal screen obtains the session; leaving it (by any kind of
    // back) used to leave the list showing the state from before.
    final session = container.read(sshSessionsProvider).obtain(host);
    session.status = SshStatus.connected;
    session.toggleCtrl(); // any change notifies
    await tester.pump();
    expect(iconColor(), Colors.green);

    container.read(sshSessionsProvider).close(host.id);
    await tester.pump();
    expect(iconColor(), isNull);
  });
}

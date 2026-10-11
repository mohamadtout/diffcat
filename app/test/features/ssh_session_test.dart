import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:git_reviewer/core/storage/storage.dart';
import 'package:git_reviewer/features/terminal/ssh_host.dart';
import 'package:git_reviewer/features/terminal/ssh_session.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('a kept session that is not connected takes the edited host', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(overrides: [sharedPrefsProvider.overrideWithValue(prefs)]);
    addTearDown(container.dispose);
    final registry = container.read(sshSessionsProvider);

    const typo = SshHost(id: 'h', label: 'Box', host: 'bxo.local', port: 22, username: 'me', auth: SshAuth.key);
    final session = registry.obtain(typo);
    session.status = SshStatus.failed; // the typo didn't connect

    const fixed = SshHost(id: 'h', label: 'Box', host: 'box.local', port: 2222, username: 'me', auth: SshAuth.key);
    expect(registry.obtain(fixed), same(session), reason: 'the session (and its scrollback) is kept');
    expect(session.host.address, fixed.address);

    // An open connection keeps the details it was opened with.
    session.status = SshStatus.connected;
    session.updateHost(typo);
    expect(session.host.address, fixed.address);
  });
}

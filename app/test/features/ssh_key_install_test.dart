import 'package:flutter_test/flutter_test.dart';
import 'package:git_reviewer/features/terminal/ssh_host.dart';
import 'package:git_reviewer/features/terminal/ssh_session.dart';

void main() {
  test('generated keys produce a shell-safe install command', () {
    final key = generateEd25519("diffcat@Sam's iPad (2)");
    expect(key.publicLine, matches(RegExp(r'^ssh-ed25519 \S+ diffcat@Sam-s-iPad--2-$')));
    final cmd = authorizedKeysInstallCommand(key.publicLine);
    expect(cmd, contains("grep -qxF '${key.publicLine}' ~/.ssh/authorized_keys"));
    expect(cmd, contains("echo '${key.publicLine}' >> ~/.ssh/authorized_keys"));
    expect(cmd, startsWith('umask 077'));
    expect(cmd, endsWith('echo $keyInstalledMarker'));
  });

  test('install command rejects anything but a one-line public key', () {
    for (final bad in [
      '',
      'not a key',
      "ssh-ed25519 AAAA'; rm -rf ~; echo '",
      r'ssh-ed25519 AAAA $(reboot)',
      'ssh-ed25519 AAAA comment\nssh-ed25519 BBBB other',
      '-----BEGIN OPENSSH PRIVATE KEY-----',
    ]) {
      expect(() => authorizedKeysInstallCommand(bad), throwsArgumentError, reason: bad);
    }
  });
}

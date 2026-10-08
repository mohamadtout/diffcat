import 'dart:async';
import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xterm/xterm.dart';

import '../../core/storage/storage.dart';
import '../commands/key_sequence.dart';
import 'ssh_host.dart';

enum SshStatus { idle, connecting, connected, disconnected, failed }

/// Asks the user whether to trust a host key. [previous] is non-null when the
/// key CHANGED since last time (possible man-in-the-middle).
typedef HostKeyPrompt = Future<bool> Function(String type, String fingerprint, String? previous);

/// One interactive SSH shell rendered into an xterm [Terminal].
class SshSessionController extends ChangeNotifier {
  SshSessionController({required this.host, required this.secure, required this.knownHosts});

  final SshHost host;
  final SecureStore secure;
  final KnownHosts knownHosts;

  final terminal = Terminal(maxLines: 10000);
  SSHClient? _client;
  SSHSession? _session;
  final _subs = <StreamSubscription<String>>[];

  SshStatus status = SshStatus.idle;
  String? error;

  /// Sticky modifiers from the on-screen toolbar; applied to the next typed key.
  bool ctrlLatched = false;
  bool altLatched = false;
  bool _macro = false;

  /// Set by the UI before [connect] so host-key prompts can show a dialog.
  HostKeyPrompt? onHostKeyPrompt;

  bool get isActive => status == SshStatus.connecting || status == SshStatus.connected;

  Future<void> connect() async {
    if (isActive) return;
    _setStatus(SshStatus.connecting);
    terminal.write('\x1b[2mConnecting to ${host.address}…\x1b[0m\r\n');
    try {
      List<SSHKeyPair>? identities;
      String? password;
      if (host.auth == SshAuth.key) {
        final pem = await secure.read(StoreKeys.sshPrivateKey(host.id));
        if (pem == null) throw StateError('No private key saved for this host.');
        final pass = await secure.read(StoreKeys.sshPassphrase(host.id));
        identities = SSHKeyPair.fromPem(pem, pass);
      } else {
        password = await secure.read(StoreKeys.sshPassword(host.id));
      }
      final client = _client = await openSshClient(
        host,
        identities: identities,
        password: password,
        onVerifyHostKey: hostKeyVerifier(knownHosts, host, () => onHostKeyPrompt),
      );
      final session = _session = await client.shell(
        pty: SSHPtyConfig(type: 'xterm-256color', width: terminal.viewWidth, height: terminal.viewHeight),
      );
      terminal.onOutput = _send;
      terminal.onResize = session.resizeTerminal;
      const decoder = Utf8Decoder(allowMalformed: true);
      _subs
        ..add(session.stdout.cast<List<int>>().transform(decoder).listen(terminal.write))
        ..add(session.stderr.cast<List<int>>().transform(decoder).listen(terminal.write));
      unawaited(session.done.then((_) => _closed(), onError: _closed));
      _setStatus(SshStatus.connected);
      if (host.startupCommand.trim().isNotEmpty) sendKeys(host.startupCommand);
    } catch (e) {
      _teardown();
      error = e.toString();
      terminal.write('\r\n\x1b[31m✖ $error\x1b[0m\r\n');
      _setStatus(SshStatus.failed);
    }
  }

  void disconnect() {
    _teardown();
    terminal.write('\r\n\x1b[2m[disconnected]\x1b[0m\r\n');
    _setStatus(SshStatus.disconnected);
  }

  /// Types a key-notation sequence (custom buttons, startup command).
  void sendKeys(String notation) {
    if (status != SshStatus.connected) return;
    _macro = true;
    try {
      for (final a in parseKeySequence(notation)) {
        switch (a) {
          case TextKeys(:final text):
            terminal.textInput(text);
          case SpecialKeyPress(:final key, :final shift):
            terminal.keyInput(_terminalKey(key), shift: shift);
          case ChordKeys(:final char, :final ctrl, :final alt):
            terminal.charInput(char.codeUnitAt(0), ctrl: ctrl, alt: alt);
        }
      }
    } finally {
      _macro = false;
    }
  }

  void pressKey(SpecialKey key) {
    if (status != SshStatus.connected) return;
    terminal.keyInput(_terminalKey(key), ctrl: _consumeCtrl(), alt: _consumeAlt());
  }

  void toggleCtrl() {
    ctrlLatched = !ctrlLatched;
    notifyListeners();
  }

  void toggleAlt() {
    altLatched = !altLatched;
    notifyListeners();
  }

  void _send(String data) {
    final session = _session;
    if (session == null) return;
    var out = data;
    if (!_macro && data.length == 1) {
      if (ctrlLatched) {
        final c = data.toLowerCase().codeUnitAt(0);
        // a-z and @ [ \ ] ^ _ map to control codes 0-31.
        if ((c >= 0x61 && c <= 0x7a) || (c >= 0x40 && c <= 0x5f)) {
          out = String.fromCharCode(c & 0x1f);
        }
        _consumeCtrl();
      }
      if (altLatched) {
        out = '\x1b$out';
        _consumeAlt();
      }
    }
    session.write(Uint8List.fromList(utf8.encode(out)));
  }

  bool _consumeCtrl() {
    final v = ctrlLatched;
    if (v) {
      ctrlLatched = false;
      notifyListeners();
    }
    return v;
  }

  bool _consumeAlt() {
    final v = altLatched;
    if (v) {
      altLatched = false;
      notifyListeners();
    }
    return v;
  }

  void _closed([Object? e]) {
    if (status != SshStatus.connected) return;
    _teardown();
    terminal.write('\r\n\x1b[2m[session closed${e == null ? '' : ': $e'}]\x1b[0m\r\n');
    _setStatus(SshStatus.disconnected);
  }

  void _teardown() {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    _session?.close();
    _client?.close();
    _session = null;
    _client = null;
    terminal.onOutput = null;
    terminal.onResize = null;
  }

  void _setStatus(SshStatus s) {
    status = s;
    notifyListeners();
  }

  @override
  void dispose() {
    _teardown();
    super.dispose();
  }
}

/// Opens an authenticated SSH connection to [host].
Future<SSHClient> openSshClient(
  SshHost host, {
  List<SSHKeyPair>? identities,
  String? password,
  required SSHHostkeyVerifyHandler onVerifyHostKey,
}) async {
  final socket = await SSHSocket.connect(host.host, host.port, timeout: const Duration(seconds: 12));
  return SSHClient(
    socket,
    username: host.username,
    identities: identities,
    onPasswordRequest: password == null ? null : () => password,
    onVerifyHostKey: onVerifyHostKey,
  );
}

/// Trust-on-first-use check against [knownHosts]. Unknown or changed keys go
/// to the prompt (read lazily, so the UI can attach it after construction).
SSHHostkeyVerifyHandler hostKeyVerifier(KnownHosts knownHosts, SshHost host, HostKeyPrompt? Function() prompt) =>
    (type, fp) async {
      final fingerprint = utf8.decode(fp, allowMalformed: true); // `SHA256:<base64>`, as ssh-keygen -lf prints
      final known = knownHosts.fingerprintFor(host.host, host.port);
      if (known == fingerprint) return true;
      final ask = prompt();
      final ok = ask != null && await ask(type, fingerprint, known);
      if (ok) await knownHosts.trust(host.host, host.port, fingerprint);
      return ok;
    };

/// Shell command that appends [publicLine] to `~/.ssh/authorized_keys` unless
/// it's already there (what `ssh-copy-id` does). The line is interpolated into
/// a shell command, so anything but a plain one-line public key is rejected.
String authorizedKeysInstallCommand(String publicLine) {
  final line = publicLine.trim();
  final valid = RegExp(r'^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp(256|384|521)) [A-Za-z0-9+/]+=* ?[A-Za-z0-9@._-]*$');
  if (!valid.hasMatch(line)) throw ArgumentError.value(publicLine, 'publicLine', 'not a one-line OpenSSH public key');
  return 'umask 077 && mkdir -p ~/.ssh && touch ~/.ssh/authorized_keys && '
      "{ grep -qxF '$line' ~/.ssh/authorized_keys || echo '$line' >> ~/.ssh/authorized_keys; } && "
      'echo $keyInstalledMarker';
}

const keyInstalledMarker = 'GIT_REVIEWER_KEY_INSTALLED';

/// Authorizes [publicLine] on the host [client] is logged in to.
Future<void> installPublicKey(SSHClient client, String publicLine) async {
  final out = utf8.decode(await client.run(authorizedKeysInstallCommand(publicLine)), allowMalformed: true);
  if (!out.contains(keyInstalledMarker)) throw StateError('The host did not confirm: ${out.trim()}');
}

TerminalKey _terminalKey(SpecialKey k) => switch (k) {
  SpecialKey.enter => TerminalKey.enter,
  SpecialKey.escape => TerminalKey.escape,
  SpecialKey.tab => TerminalKey.tab,
  SpecialKey.backspace => TerminalKey.backspace,
  SpecialKey.delete => TerminalKey.delete,
  SpecialKey.up => TerminalKey.arrowUp,
  SpecialKey.down => TerminalKey.arrowDown,
  SpecialKey.left => TerminalKey.arrowLeft,
  SpecialKey.right => TerminalKey.arrowRight,
  SpecialKey.home => TerminalKey.home,
  SpecialKey.end => TerminalKey.end,
  SpecialKey.pageUp => TerminalKey.pageUp,
  SpecialKey.pageDown => TerminalKey.pageDown,
  SpecialKey.f1 => TerminalKey.f1,
  SpecialKey.f2 => TerminalKey.f2,
  SpecialKey.f3 => TerminalKey.f3,
  SpecialKey.f4 => TerminalKey.f4,
  SpecialKey.f5 => TerminalKey.f5,
  SpecialKey.f6 => TerminalKey.f6,
  SpecialKey.f7 => TerminalKey.f7,
  SpecialKey.f8 => TerminalKey.f8,
  SpecialKey.f9 => TerminalKey.f9,
  SpecialKey.f10 => TerminalKey.f10,
  SpecialKey.f11 => TerminalKey.f11,
  SpecialKey.f12 => TerminalKey.f12,
};

/// Keeps sessions alive while navigating around the app.
class SshSessionRegistry {
  SshSessionRegistry(this._ref);
  final Ref _ref;
  final _sessions = <String, SshSessionController>{};

  SshSessionController obtain(SshHost host) => _sessions.putIfAbsent(
    host.id,
    () => SshSessionController(
      host: host,
      secure: _ref.read(secureStoreProvider),
      knownHosts: _ref.read(knownHostsProvider),
    ),
  );

  SshSessionController? existing(String hostId) => _sessions[hostId];

  void close(String hostId) => _sessions.remove(hostId)?.dispose();

  void closeAll() {
    for (final s in _sessions.values) {
      s.dispose();
    }
    _sessions.clear();
  }
}

final sshSessionsProvider = Provider<SshSessionRegistry>((ref) {
  final registry = SshSessionRegistry(ref);
  ref.onDispose(registry.closeAll);
  return registry;
});

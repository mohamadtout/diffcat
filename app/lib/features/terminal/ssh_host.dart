import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinenacl/ed25519.dart' as ed;

import '../../core/storage/storage.dart';

enum SshAuth { password, key }

/// A machine you can SSH into to run real git / lazygit. Secrets (password,
/// private key, passphrase) live in secure storage keyed by [id], never here.
class SshHost {
  const SshHost({
    required this.id,
    required this.label,
    required this.host,
    required this.port,
    required this.username,
    required this.auth,
    this.startupCommand = '',
  });

  factory SshHost.fromJson(Map<String, dynamic> j) => SshHost(
    id: j['id'] as String,
    label: j['label'] as String,
    host: j['host'] as String,
    port: (j['port'] as int?) ?? 22,
    username: j['username'] as String,
    auth: SshAuth.values.byName((j['auth'] as String?) ?? 'key'),
    startupCommand: (j['startupCommand'] as String?) ?? '',
  );

  final String id;
  final String label;
  final String host;
  final int port;
  final String username;
  final SshAuth auth;

  /// Typed after login, e.g. `cd ~/code/app && lazygit` (key notation allowed).
  final String startupCommand;

  String get address => '$username@$host${port == 22 ? '' : ':$port'}';

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'host': host,
    'port': port,
    'username': username,
    'auth': auth.name,
    'startupCommand': startupCommand,
  };
}

final sshHostsProvider = NotifierProvider<SshHostsNotifier, List<SshHost>>(SshHostsNotifier.new);

class SshHostsNotifier extends Notifier<List<SshHost>> {
  @override
  List<SshHost> build() =>
      ref.watch(sharedPrefsProvider).readJsonList(StoreKeys.sshHosts).map(SshHost.fromJson).toList();

  SshHost? byId(String id) => state.where((h) => h.id == id).firstOrNull;

  Future<void> upsert(SshHost h) => _save([
    for (final e in state)
      if (e.id == h.id) h else e,
    if (!state.any((e) => e.id == h.id)) h,
  ]);

  Future<void> remove(String id) async {
    final secure = ref.read(secureStoreProvider);
    await secure.delete(StoreKeys.sshPassword(id));
    await secure.delete(StoreKeys.sshPrivateKey(id));
    await secure.delete(StoreKeys.sshPassphrase(id));
    await _save(state.where((h) => h.id != id).toList());
  }

  Future<void> _save(List<SshHost> list) async {
    state = list;
    await ref.read(sharedPrefsProvider).writeJsonList(StoreKeys.sshHosts, list.map((h) => h.toJson()).toList());
  }
}

/// Trust-on-first-use host key store (like ~/.ssh/known_hosts).
class KnownHosts {
  KnownHosts(this._read, this._write);

  final Map<String, String> Function() _read;
  final Future<void> Function(Map<String, String>) _write;

  static String key(String host, int port) => '$host:$port';

  String? fingerprintFor(String host, int port) => _read()[key(host, port)];

  Future<void> trust(String host, int port, String fingerprint) => _write({..._read(), key(host, port): fingerprint});

  Future<void> forget(String host, int port) => _write({..._read()}..remove(key(host, port)));
}

final knownHostsProvider = Provider<KnownHosts>((ref) {
  final prefs = ref.watch(sharedPrefsProvider);
  return KnownHosts(
    () => prefs.readStringMap(StoreKeys.knownHosts),
    (m) => prefs.writeStringMap(StoreKeys.knownHosts, m),
  );
});

/// A freshly generated Ed25519 key pair in OpenSSH formats.
class GeneratedKey {
  const GeneratedKey({required this.privatePem, required this.publicLine});
  final String privatePem;

  /// `ssh-ed25519 AAAA… comment` — append to ~/.ssh/authorized_keys.
  final String publicLine;
}

/// Generates the key on-device so the private key never leaves the phone.
GeneratedKey generateEd25519(String comment) {
  comment = comment.replaceAll(RegExp(r'[^A-Za-z0-9@._-]'), '-'); // keep authorized_keys lines shell-safe
  final signing = ed.SigningKey.generate();
  final pub = Uint8List.fromList(signing.verifyKey.asTypedList);
  final priv = Uint8List.fromList(signing.asTypedList); // seed ‖ public (64 bytes)
  final pair = OpenSSHEd25519KeyPair(pub, priv, comment);
  final blob = pair.toPublicKey().encode();
  return GeneratedKey(privatePem: pair.toPem(), publicLine: 'ssh-ed25519 ${base64.encode(blob)} $comment');
}

/// Public `authorized_keys` line for a stored private key, if parseable.
String? publicLineFor(String privatePem, {String? passphrase, String comment = ''}) {
  try {
    final pairs = SSHKeyPair.fromPem(privatePem, passphrase);
    if (pairs.isEmpty) return null;
    final p = pairs.first;
    return '${p.name} ${base64.encode(p.toPublicKey().encode())} $comment'.trim();
  } catch (_) {
    return null;
  }
}

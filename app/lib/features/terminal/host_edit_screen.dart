import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/layout/readable_width.dart';
import '../../core/storage/storage.dart';
import '../../core/theme/app_theme.dart';
import 'host_key_dialog.dart';
import 'ssh_host.dart';
import 'ssh_session.dart';

class HostEditScreen extends ConsumerStatefulWidget {
  const HostEditScreen({super.key, this.hostId});

  final String? hostId;

  @override
  ConsumerState<HostEditScreen> createState() => _HostEditScreenState();
}

class _HostEditScreenState extends ConsumerState<HostEditScreen> {
  final _form = GlobalKey<FormState>();
  final _label = TextEditingController();
  final _host = TextEditingController();
  final _port = TextEditingController(text: '22');
  final _user = TextEditingController();
  final _password = TextEditingController();
  final _key = TextEditingController();
  final _passphrase = TextEditingController();
  final _startup = TextEditingController();
  SshAuth _auth = SshAuth.key;
  String? _publicLine;
  bool _installing = false;
  late final String _id = widget.hostId ?? DateTime.now().microsecondsSinceEpoch.toString();

  @override
  void initState() {
    super.initState();
    final existing = widget.hostId == null ? null : ref.read(sshHostsProvider.notifier).byId(widget.hostId!);
    if (existing != null) {
      _label.text = existing.label;
      _host.text = existing.host;
      _port.text = existing.port.toString();
      _user.text = existing.username;
      _startup.text = existing.startupCommand;
      _auth = existing.auth;
      _loadSecrets();
    }
  }

  Future<void> _loadSecrets() async {
    final s = ref.read(secureStoreProvider);
    final key = await s.read(StoreKeys.sshPrivateKey(_id));
    final pass = await s.read(StoreKeys.sshPassphrase(_id));
    final pw = await s.read(StoreKeys.sshPassword(_id));
    if (!mounted) return;
    setState(() {
      _key.text = key ?? '';
      _passphrase.text = pass ?? '';
      _password.text = pw ?? '';
      if (key != null) _publicLine = publicLineFor(key, passphrase: pass, comment: 'diffcat');
    });
  }

  @override
  void dispose() {
    for (final c in [_label, _host, _port, _user, _password, _key, _passphrase, _startup]) {
      c.dispose();
    }
    super.dispose();
  }

  void _generate() {
    final k = generateEd25519('diffcat@${_label.text.isEmpty ? 'phone' : _label.text.replaceAll(' ', '-')}');
    setState(() {
      _key.text = k.privatePem;
      _passphrase.clear();
      _publicLine = k.publicLine;
    });
  }

  SshHost _draft() => SshHost(
    id: _id,
    label: _label.text.trim().isEmpty ? _host.text.trim() : _label.text.trim(),
    host: _host.text.trim(),
    port: int.parse(_port.text.trim()),
    username: _user.text.trim(),
    auth: _auth,
    startupCommand: _startup.text,
  );

  /// Like `ssh-copy-id`: logs in once with the account password (not saved)
  /// and adds this device's public key to the host's authorized_keys.
  Future<void> _installOnHost() async {
    if (!_form.currentState!.validate() || _publicLine == null) return;
    final host = _draft();
    final password = await _askPassword(host);
    if (password == null || password.isEmpty || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _installing = true);
    SSHClient? client;
    try {
      client = await openSshClient(
        host,
        password: password,
        onVerifyHostKey: hostKeyVerifier(
          ref.read(knownHostsProvider),
          host,
          () =>
              (type, fp, previous) =>
                  confirmHostKey(context, hostName: host.host, type: type, fingerprint: fp, previous: previous),
        ),
      );
      await installPublicKey(client, _publicLine!);
      messenger.showSnackBar(SnackBar(content: Text('Key installed on ${host.address}. Save, then connect.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text("Couldn't install the key: $e")));
    } finally {
      await client?.close();
      if (mounted) setState(() => _installing = false);
    }
  }

  Future<String?> _askPassword(SshHost host) => showDialog<String>(
    context: context,
    builder: (_) => PasswordDialog(address: host.address),
  );

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final host = _draft();
    final s = ref.read(secureStoreProvider);
    if (_auth == SshAuth.password) {
      await s.write(StoreKeys.sshPassword(_id), _password.text);
      await s.delete(StoreKeys.sshPrivateKey(_id));
      await s.delete(StoreKeys.sshPassphrase(_id));
    } else {
      await s.write(StoreKeys.sshPrivateKey(_id), _key.text.trim());
      await s.write(StoreKeys.sshPassphrase(_id), _passphrase.text);
      await s.delete(StoreKeys.sshPassword(_id));
    }
    await ref.read(sshHostsProvider.notifier).upsert(host);
    if (mounted) context.pop();
  }

  String? _required(String? v) => (v == null || v.trim().isEmpty) ? 'Required' : null;

  @override
  Widget build(BuildContext context) {
    final mono = TextStyle(fontFamily: AppTheme.monoFamily, fontSize: 12);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.hostId == null ? 'New SSH host' : 'Edit SSH host'),
        actions: [TextButton(onPressed: _save, child: const Text('Save'))],
      ),
      body: Form(
        key: _form,
        child: ReadableWidth(
          maxWidth: 640,
          builder: (sides) => ListView(
            padding: sides + const EdgeInsets.all(16),
            children: [
              TextFormField(
                controller: _label,
                decoration: const InputDecoration(labelText: 'Name (e.g. Dev box)'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: TextFormField(
                      controller: _host,
                      validator: _required,
                      keyboardType: TextInputType.url,
                      autocorrect: false,
                      decoration: const InputDecoration(labelText: 'Host / IP (Tailscale name works)'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _port,
                      keyboardType: TextInputType.number,
                      validator: (v) {
                        final n = int.tryParse(v ?? '');
                        return n == null || n < 1 || n > 65535 ? 'Invalid' : null;
                      },
                      decoration: const InputDecoration(labelText: 'Port'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _user,
                validator: _required,
                autocorrect: false,
                decoration: const InputDecoration(labelText: 'Username'),
              ),
              const SizedBox(height: 20),
              SegmentedButton<SshAuth>(
                segments: const [
                  ButtonSegment(value: SshAuth.key, icon: Icon(Icons.key), label: Text('Key')),
                  ButtonSegment(value: SshAuth.password, icon: Icon(Icons.password), label: Text('Password')),
                ],
                selected: {_auth},
                onSelectionChanged: (s) => setState(() => _auth = s.first),
              ),
              const SizedBox(height: 12),
              if (_auth == SshAuth.password)
                TextFormField(
                  controller: _password,
                  obscureText: true,
                  validator: _required,
                  decoration: const InputDecoration(labelText: 'Password'),
                )
              else ...[
                OutlinedButton.icon(
                  icon: const Icon(Icons.auto_fix_high),
                  label: const Text('Generate Ed25519 key on this device'),
                  onPressed: _generate,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _key,
                  validator: _required,
                  style: mono,
                  minLines: 3,
                  maxLines: 6,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: const InputDecoration(
                    labelText: 'Private key (OpenSSH / PEM)',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) =>
                      setState(() => _publicLine = publicLineFor(v, passphrase: _passphrase.text, comment: 'diffcat')),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _passphrase,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Key passphrase (if any)'),
                ),
                if (_publicLine != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    'Public key — add to ~/.ssh/authorized_keys on the host:',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: SelectableText(_publicLine!, style: mono),
                  ),
                  Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 8,
                    children: [
                      TextButton.icon(
                        icon: const Icon(Icons.copy, size: 18),
                        label: const Text('Copy public key'),
                        onPressed: () => Clipboard.setData(ClipboardData(text: _publicLine!)),
                      ),
                      FilledButton.tonalIcon(
                        icon: _installing
                            ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.login, size: 18),
                        label: const Text('Install on host…'),
                        onPressed: _installing ? null : _installOnHost,
                      ),
                    ],
                  ),
                ],
              ],
              const SizedBox(height: 20),
              TextFormField(
                controller: _startup,
                style: mono,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Startup command (optional)',
                  hintText: 'cd ~/code/my-repo && lazygit<enter>',
                  helperText: 'Typed after login. Key notation supported.',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Asks for the host password once. Owns its controller so it is disposed
/// only after the dialog's exit animation (which still renders the field).
class PasswordDialog extends StatefulWidget {
  const PasswordDialog({super.key, required this.address});

  final String address;

  @override
  State<PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<PasswordDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Install key on ${widget.address}'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("Enter the account's password once. It's used to add this device's key and is not saved."),
        const SizedBox(height: 12),
        TextField(
          controller: _controller,
          autofocus: true,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Password'),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
      ],
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(onPressed: () => Navigator.pop(context, _controller.text), child: const Text('Install')),
    ],
  );
}

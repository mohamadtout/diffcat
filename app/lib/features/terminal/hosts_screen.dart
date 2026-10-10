import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/layout/readable_width.dart';
import '../../core/routing/routes.dart';
import 'ssh_host.dart';
import 'ssh_session.dart';

/// Terminal tab root: your SSH hosts.
class HostsScreen extends ConsumerWidget {
  const HostsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hosts = ref.watch(sshHostsProvider);
    final registry = ref.watch(sshSessionsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Terminal')),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('Add host'),
        onPressed: () => context.push(Routes.hostEdit(null)),
      ),
      // Rebuilds when a session connects or drops, so the green icon is right
      // however the terminal was left (app bar back or the system gesture).
      body: ListenableBuilder(
        listenable: registry,
        builder: (context, _) => ReadableWidth(
          builder: (sides) => ListView(
            padding: sides + const EdgeInsets.only(bottom: 96),
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Text(
                  'A real shell on a machine you own (laptop, VPS, home server via '
                  'Tailscale). Run lazygit or any git command there — nothing is '
                  'cloned to the phone.',
                ),
              ),
              if (hosts.isEmpty)
                const ListTile(
                  leading: Icon(Icons.info_outline),
                  title: Text('No hosts yet'),
                  subtitle: Text('Add one, then see SETUP.md § SSH host for server-side steps.'),
                ),
              for (final h in hosts)
                ListTile(
                  leading: Icon(
                    Icons.dns_outlined,
                    color: (registry.existing(h.id)?.status == SshStatus.connected) ? Colors.green : null,
                  ),
                  title: Text(h.label),
                  subtitle: Text(h.address),
                  onTap: () => context.push(Routes.terminalSession(h.id)),
                  trailing: PopupMenuButton<String>(
                    onSelected: (v) async {
                      switch (v) {
                        case 'edit':
                          await context.push(Routes.hostEdit(h.id));
                        case 'forget':
                          await ref.read(knownHostsProvider).forget(h.host, h.port);
                        case 'delete':
                          registry.close(h.id);
                          await ref.read(sshHostsProvider.notifier).remove(h.id);
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'edit', child: Text('Edit')),
                      PopupMenuItem(value: 'forget', child: Text('Forget host key')),
                      PopupMenuItem(value: 'delete', child: Text('Delete')),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

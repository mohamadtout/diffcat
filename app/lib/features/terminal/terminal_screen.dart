import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:xterm/xterm.dart';

import '../../core/routing/routes.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/text_size_sheet.dart';
import '../commands/custom_command.dart';
import '../commands/key_sequence.dart';
import 'host_key_dialog.dart';
import 'ssh_host.dart';
import 'ssh_session.dart';

class TerminalScreen extends ConsumerStatefulWidget {
  const TerminalScreen({super.key, required this.hostId});

  final String hostId;

  @override
  ConsumerState<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends ConsumerState<TerminalScreen> {
  SshSessionController? _session;
  double _fontSize = 13;

  @override
  void initState() {
    super.initState();
    final host = ref.read(sshHostsProvider.notifier).byId(widget.hostId);
    if (host == null) return;
    final s = _session = ref.read(sshSessionsProvider).obtain(host);
    s.onHostKeyPrompt = _confirmHostKey;
    // Connect after the first layout so the PTY gets the real terminal size.
    if (!s.isActive && s.status != SshStatus.disconnected) {
      WidgetsBinding.instance.addPostFrameCallback((_) => s.connect());
    }
  }

  Future<bool> _confirmHostKey(String type, String fp, String? previous) =>
      confirmHostKey(context, hostName: _session!.host.host, type: type, fingerprint: fp, previous: previous);

  @override
  Widget build(BuildContext context) {
    final session = _session;
    if (session == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const EmptyView(icon: Icons.dns_outlined, message: 'Host not found.'),
      );
    }
    final buttons = ref.watch(customCommandsProvider).where((c) => c.target == CommandTarget.ssh).toList();
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(session.host.label),
              Text('${session.host.address} · ${session.status.name}', style: Theme.of(context).textTheme.labelSmall),
            ],
          ),
          actions: [
            if (session.isActive)
              IconButton(tooltip: 'Disconnect', icon: const Icon(Icons.link_off), onPressed: session.disconnect)
            else
              IconButton(tooltip: 'Reconnect', icon: const Icon(Icons.refresh), onPressed: session.connect),
            PopupMenuButton<String>(
              onSelected: (v) async {
                switch (v) {
                  case 'paste':
                    final data = await Clipboard.getData(Clipboard.kTextPlain);
                    if (data?.text != null) session.terminal.paste(data!.text!);
                  case 'textSize':
                    if (context.mounted) {
                      await showTextSizeSheet(
                        context,
                        value: _fontSize,
                        min: 8,
                        max: 24,
                        onChanged: (v) => setState(() => _fontSize = v),
                      );
                    }
                  case 'buttons':
                    if (context.mounted) await context.push(Routes.commands);
                  case 'close':
                    ref.read(sshSessionsProvider).close(widget.hostId);
                    if (context.mounted) context.pop();
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'paste', child: Text('Paste')),
                PopupMenuItem(value: 'textSize', child: Text('Text size…')),
                PopupMenuItem(value: 'buttons', child: Text('Edit buttons')),
                PopupMenuItem(value: 'close', child: Text('Close session')),
              ],
            ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: Column(
            children: [
              Expanded(
                child: TerminalView(
                  session.terminal,
                  autofocus: true,
                  backgroundOpacity: 1,
                  textStyle: TerminalStyle(fontSize: _fontSize, fontFamily: AppTheme.monoFamily),
                  padding: const EdgeInsets.all(4),
                ),
              ),
              if (buttons.isNotEmpty)
                SizedBox(
                  height: 40,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    children: [
                      for (final b in buttons)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
                          child: ActionChip(
                            visualDensity: VisualDensity.compact,
                            label: Text(b.label),
                            tooltip: b.command,
                            onPressed: () => session.sendKeys(b.command),
                          ),
                        ),
                    ],
                  ),
                ),
              _KeyToolbar(session: session),
            ],
          ),
        ),
      ),
    );
  }
}

/// Keys a phone keyboard lacks but TUIs like lazygit need.
class _KeyToolbar extends StatelessWidget {
  const _KeyToolbar({required this.session});

  final SshSessionController session;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget key(String label, VoidCallback onTap, {bool active = false, String? tooltip}) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Material(
        color: active ? scheme.primary : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: Container(
            constraints: const BoxConstraints(minWidth: 40),
            height: 36,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              label,
              style: TextStyle(
                fontFamily: AppTheme.monoFamily,
                color: active ? scheme.onPrimary : scheme.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );

    void text(String t) => session.sendKeys(t == '<' ? '<lt>' : t);

    return Container(
      color: scheme.surfaceContainer,
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        children: [
          key('esc', () => session.pressKey(SpecialKey.escape)),
          key('tab', () => session.pressKey(SpecialKey.tab)),
          key('ctrl', session.toggleCtrl, active: session.ctrlLatched),
          key('alt', session.toggleAlt, active: session.altLatched),
          key('↑', () => session.pressKey(SpecialKey.up)),
          key('↓', () => session.pressKey(SpecialKey.down)),
          key('←', () => session.pressKey(SpecialKey.left)),
          key('→', () => session.pressKey(SpecialKey.right)),
          key('⏎', () => session.pressKey(SpecialKey.enter)),
          key('pgup', () => session.pressKey(SpecialKey.pageUp)),
          key('pgdn', () => session.pressKey(SpecialKey.pageDown)),
          key('home', () => session.pressKey(SpecialKey.home)),
          key('end', () => session.pressKey(SpecialKey.end)),
          for (final c in ['|', '/', '-', '~', ':', '[', ']', '<', '>', '{', '}', r'$', '*', '?', '@'])
            key(c, () => text(c)),
        ],
      ),
    );
  }
}

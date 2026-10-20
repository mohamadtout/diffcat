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
import 'terminal_appearance.dart';
import 'terminal_appearance_screen.dart';
import 'terminal_chrome.dart';
import 'terminal_keyboard.dart';
import 'terminal_themes.dart';

class TerminalScreen extends ConsumerStatefulWidget {
  const TerminalScreen({super.key, required this.hostId});

  final String hostId;

  @override
  ConsumerState<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends ConsumerState<TerminalScreen> {
  SshSessionController? _session;
  final _focus = FocusNode();
  final _scroll = ScrollController();
  final _keyboard = GlobalKey<TerminalKeyboardState>();
  final _view = GlobalKey<TerminalViewState>();

  @override
  void initState() {
    super.initState();
    final host = ref.read(sshHostsProvider.notifier).byId(widget.hostId);
    if (host == null) return;
    final s = _session = ref.read(sshSessionsProvider).obtain(host);
    s.onHostKeyPrompt = _confirmHostKey;
    // Connect after the first layout so the PTY gets the real terminal size.
    if (!s.isActive && s.status != SshStatus.disconnected) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _connect());
    }
  }

  @override
  void dispose() {
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Before keys sent other than by typing (see [TerminalKeyboardState.finishComposing]).
  void _finishComposing() => _keyboard.currentState?.finishComposing();

  void _scrollToBottom() {
    if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
  }

  void _connect() {
    final session = _session;
    if (session == null) return;
    // Reconnect uses the host as saved now, if it was edited meanwhile.
    if (ref.read(sshHostsProvider.notifier).byId(widget.hostId) case final saved?) session.updateHost(saved);
    session.connect(shellIntegration: ref.read(terminalAppearanceProvider).shellIntegration);
  }

  Future<bool> _confirmHostKey(String type, String fp, String? previous) =>
      confirmHostKey(context, hostName: _session!.host.host, type: type, fingerprint: fp, previous: previous);

  Widget _statusBar(SshSessionController session, TerminalAppearance look, TerminalTheme theme) => TerminalStatusBar(
    data: StatusBarData(
      host: session.host.address,
      cwd: session.cwd,
      git: session.git,
      connected: session.status == SshStatus.connected,
    ),
    appearance: look,
    theme: theme,
    onTap: session.refreshGit,
    onSetup: () => showShellIntegrationSheet(context),
  );

  @override
  Widget build(BuildContext context) {
    final session = _session;
    if (session == null) {
      return Scaffold(
        appBar: AppBar(),
        body: EmptyView(
          icon: Icons.dns_outlined,
          message: 'Host not found. It may have been deleted.',
          action: FilledButton.tonal(onPressed: () => context.go(Routes.terminal), child: const Text('Back to hosts')),
        ),
      );
    }
    final buttons = ref.watch(customCommandsProvider).where((c) => c.target == CommandTarget.ssh).toList();
    final look = ref.watch(terminalAppearanceProvider);
    final preset = presetFor(look.theme, appIsDark: Theme.of(context).brightness == Brightness.dark);
    final theme = preset.theme;
    // Following the app keeps the app's own toolbar colors; a chosen theme
    // tints the toolbar to match the terminal.
    final tint = look.theme == followAppPreset ? null : theme;
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
              IconButton(tooltip: 'Reconnect', icon: const Icon(Icons.refresh), onPressed: _connect),
            PopupMenuButton<String>(
              onSelected: (v) async {
                switch (v) {
                  case 'paste':
                    final data = await Clipboard.getData(Clipboard.kTextPlain);
                    if (data?.text != null) {
                      _finishComposing();
                      session.terminal.paste(data!.text!);
                    }
                  case 'textSize':
                    if (context.mounted) {
                      await showTextSizeSheet(
                        context,
                        value: look.fontSize,
                        min: TerminalAppearance.minFontSize,
                        max: TerminalAppearance.maxFontSize,
                        onChanged: (v) =>
                            ref.read(terminalAppearanceProvider.notifier).update((a) => a.copyWith(fontSize: v)),
                      );
                    }
                  case 'appearance':
                    if (context.mounted) await context.push(Routes.terminalAppearance);
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
                PopupMenuItem(value: 'appearance', child: Text('Appearance…')),
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
              if (look.statusBar && look.statusPosition == StatusBarPosition.top) _statusBar(session, look, theme),
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    TerminalBackdrop(appearance: look, theme: theme),
                    TerminalKeyboard(
                      key: _keyboard,
                      terminal: session.terminal,
                      focusNode: _focus,
                      keyboardAppearance: preset.isDark ? Brightness.dark : Brightness.light,
                      caretRect: () => _view.currentState?.globalCursorRect,
                      onInput: _scrollToBottom,
                      child: TerminalView(
                        session.terminal,
                        key: _view,
                        focusNode: _focus,
                        scrollController: _scroll,
                        autofocus: true,
                        // The keyboard goes through TerminalKeyboard instead.
                        hardwareKeyboardOnly: true,
                        onKeyEvent: (_, _) => _keyboard.currentState?.composing ?? false
                            ? KeyEventResult.skipRemainingHandlers
                            : KeyEventResult.ignored,
                        theme: theme,
                        backgroundOpacity: look.hasBackground ? 0 : 1,
                        cursorType: look.cursor,
                        textStyle: TerminalStyle(
                          fontSize: look.fontSize,
                          height: look.lineHeight,
                          fontFamily: look.font.family,
                          fontFamilyFallback: look.font.fallback,
                        ),
                        padding: const EdgeInsets.all(4),
                      ),
                    ),
                  ],
                ),
              ),
              if (look.statusBar && look.statusPosition == StatusBarPosition.bottom) _statusBar(session, look, theme),
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
                            onPressed: () {
                              _finishComposing();
                              session.sendKeys(b.command);
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              if (look.keyToolbar) _KeyToolbar(session: session, tint: tint, beforeKey: _finishComposing),
            ],
          ),
        ),
      ),
    );
  }
}

/// Keys a phone keyboard lacks but TUIs like lazygit need.
class _KeyToolbar extends StatelessWidget {
  const _KeyToolbar({required this.session, required this.beforeKey, this.tint});

  final SshSessionController session;

  /// Runs before each key, to end the keyboard's word.
  final VoidCallback beforeKey;

  /// Terminal colors to match, or null for the app's.
  final TerminalTheme? tint;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final t = tint;
    final keyColor = t == null ? scheme.surfaceContainerHighest : Color.lerp(t.background, t.foreground, 0.16)!;
    Widget key(String label, VoidCallback onTap, {bool active = false, String? tooltip}) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Material(
        color: active ? (tint?.blue ?? scheme.primary) : keyColor,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () {
            HapticFeedback.selectionClick();
            beforeKey();
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
                color: active ? (tint?.background ?? scheme.onPrimary) : (tint?.foreground ?? scheme.onSurface),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );

    void text(String t) => session.sendKeys(t == '<' ? '<lt>' : t);

    return Container(
      color: tint == null ? scheme.surfaceContainer : Color.lerp(tint!.background, tint!.foreground, 0.06),
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

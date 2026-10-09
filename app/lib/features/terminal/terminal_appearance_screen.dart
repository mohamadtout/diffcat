import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:xterm/xterm.dart';

import '../../core/layout/readable_width.dart';
import '../../core/theme/code_fonts.dart';
import 'shell_integration.dart';
import 'terminal_appearance.dart';
import 'terminal_chrome.dart';
import 'terminal_themes.dart';

/// Settings → Terminal appearance: colors, font, cursor, background and the
/// git status bar, with a live preview.
class TerminalAppearanceScreen extends ConsumerStatefulWidget {
  const TerminalAppearanceScreen({super.key});

  @override
  ConsumerState<TerminalAppearanceScreen> createState() => _TerminalAppearanceScreenState();
}

class _TerminalAppearanceScreenState extends ConsumerState<TerminalAppearanceScreen> {
  final _preview = Terminal(maxLines: 50)..write(terminalPreviewText);

  TerminalAppearanceNotifier get _notifier => ref.read(terminalAppearanceProvider.notifier);
  void _set(TerminalAppearance Function(TerminalAppearance a) change) => _notifier.update(change);

  Future<void> _pickImage() async {
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 2560,
        maxHeight: 2560,
        requestFullMetadata: false, // no photo library permission needed on iOS
      );
      if (picked == null) return;
      final dir = Directory('${(await getApplicationSupportDirectory()).path}/terminal');
      await _notifier.setImage(File(picked.path), dir);
    } on Object catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Couldn't use that image: $e")));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = ref.watch(terminalAppearanceProvider);
    final appDark = Theme.of(context).brightness == Brightness.dark;
    final preset = presetFor(a.theme, appIsDark: appDark);
    final theme = Theme.of(context);

    Widget section(String title) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Text(title, style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary)),
    );
    Widget slider(String label, double value, double min, double max, ValueChanged<double> onChanged, String shown) =>
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              SizedBox(width: 92, child: Text(label)),
              Expanded(
                child: Slider(value: value.clamp(min, max), min: min, max: max, onChanged: onChanged),
              ),
              SizedBox(width: 44, child: Text(shown, textAlign: TextAlign.end)),
            ],
          ),
        );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Terminal appearance'),
        actions: [TextButton(onPressed: _notifier.reset, child: const Text('Reset'))],
      ),
      body: ReadableWidth(
        builder: (sides) => ListView(
          padding: sides,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Column(
                  children: [
                    if (a.statusBar && a.statusPosition == StatusBarPosition.top) _previewBar(a, preset.theme),
                    SizedBox(
                      height: 210,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          TerminalBackdrop(appearance: a, theme: preset.theme),
                          TerminalView(
                            _preview,
                            readOnly: true,
                            theme: preset.theme,
                            backgroundOpacity: a.hasBackground ? 0 : 1,
                            cursorType: a.cursor,
                            alwaysShowCursor: true,
                            textStyle: TerminalStyle(
                              fontSize: a.fontSize,
                              height: a.lineHeight,
                              fontFamily: a.font.family,
                              fontFamilyFallback: a.font.fallback,
                            ),
                            padding: const EdgeInsets.all(6),
                          ),
                        ],
                      ),
                    ),
                    if (a.statusBar && a.statusPosition == StatusBarPosition.bottom) _previewBar(a, preset.theme),
                  ],
                ),
              ),
            ),

            section('Colors'),
            SizedBox(
              height: 76,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  _ThemeCard(
                    label: 'Match app',
                    theme: presetFor(followAppPreset, appIsDark: appDark).theme,
                    selected: a.theme == followAppPreset,
                    onTap: () => _set((a) => a.copyWith(theme: followAppPreset)),
                  ),
                  for (final p in terminalPresets)
                    _ThemeCard(
                      label: p.label,
                      theme: p.theme,
                      selected: a.theme == p.id,
                      onTap: () => _set((a) => a.copyWith(theme: p.id)),
                    ),
                ],
              ),
            ),

            section('Font'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final f in CodeFont.values)
                    ChoiceChip(
                      label: Text(
                        f.label,
                        style: TextStyle(fontFamily: f.family, fontFamilyFallback: f.fallback),
                      ),
                      selected: a.font == f,
                      onSelected: (_) => _set((a) => a.copyWith(font: f)),
                    ),
                ],
              ),
            ),
            slider(
              'Size',
              a.fontSize,
              TerminalAppearance.minFontSize,
              TerminalAppearance.maxFontSize,
              (v) => _set((a) => a.copyWith(fontSize: (v * 2).round() / 2)),
              a.fontSize.toStringAsFixed(a.fontSize % 1 == 0 ? 0 : 1),
            ),
            slider(
              'Line height',
              a.lineHeight,
              1,
              1.8,
              (v) => _set((a) => a.copyWith(lineHeight: (v * 20).round() / 20)),
              a.lineHeight.toStringAsFixed(2),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: SegmentedButton<TerminalCursorType>(
                segments: const [
                  ButtonSegment(value: TerminalCursorType.block, label: Text('Block')),
                  ButtonSegment(value: TerminalCursorType.underline, label: Text('Underline')),
                  ButtonSegment(value: TerminalCursorType.verticalBar, label: Text('Bar')),
                ],
                selected: {a.cursor},
                onSelectionChanged: (s) => _set((a) => a.copyWith(cursor: s.first)),
              ),
            ),

            section('Background'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SegmentedButton<BackgroundKind>(
                segments: const [
                  ButtonSegment(value: BackgroundKind.none, label: Text('Plain')),
                  ButtonSegment(value: BackgroundKind.gradient, label: Text('Gradient')),
                  ButtonSegment(value: BackgroundKind.image, label: Text('Image')),
                ],
                selected: {a.background},
                onSelectionChanged: (s) {
                  if (s.first == BackgroundKind.image && a.imagePath == null) {
                    _pickImage();
                  } else {
                    _set((a) => a.copyWith(background: s.first));
                  }
                },
              ),
            ),
            if (a.background == BackgroundKind.gradient)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final e in terminalGradients.entries)
                      Tooltip(
                        message: e.key,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () => _set((a) => a.copyWith(gradient: e.key)),
                          child: Container(
                            width: 48,
                            height: 36,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              gradient: LinearGradient(colors: e.value),
                              border: Border.all(
                                width: a.gradient == e.key ? 3 : 1,
                                color: a.gradient == e.key
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.outlineVariant,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            if (a.background == BackgroundKind.image)
              ListTile(
                leading: a.imagePath == null
                    ? const Icon(Icons.image_outlined)
                    : ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: Image.file(
                          File(a.imagePath!),
                          width: 40,
                          height: 40,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined),
                        ),
                      ),
                title: const Text('Choose image…'),
                subtitle: const Text('Copied into the app; never uploaded'),
                onTap: _pickImage,
              ),
            if (a.background != BackgroundKind.none) ...[
              slider(
                'Opacity',
                a.backgroundOpacity,
                0,
                1,
                (v) => _set((a) => a.copyWith(backgroundOpacity: v)),
                '${(a.backgroundOpacity * 100).round()}%',
              ),
              slider(
                'Blur',
                a.backgroundBlur,
                0,
                20,
                (v) => _set((a) => a.copyWith(backgroundBlur: v)),
                a.backgroundBlur.round().toString(),
              ),
            ],

            section('Status bar'),
            SwitchListTile(
              title: const Text('Show status bar'),
              subtitle: const Text('Folder and git branch of the shell'),
              value: a.statusBar,
              onChanged: (v) => _set((a) => a.copyWith(statusBar: v)),
            ),
            if (a.statusBar) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    SegmentedButton<StatusBarPosition>(
                      segments: const [
                        ButtonSegment(value: StatusBarPosition.top, label: Text('Top')),
                        ButtonSegment(value: StatusBarPosition.bottom, label: Text('Bottom')),
                      ],
                      selected: {a.statusPosition},
                      onSelectionChanged: (s) => _set((a) => a.copyWith(statusPosition: s.first)),
                    ),
                    SegmentedButton<StatusBarStyle>(
                      segments: const [
                        ButtonSegment(value: StatusBarStyle.powerline, label: Text('Powerline')),
                        ButtonSegment(value: StatusBarStyle.plain, label: Text('Plain')),
                      ],
                      selected: {a.statusStyle},
                      onSelectionChanged: (s) => _set((a) => a.copyWith(statusStyle: s.first)),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final s in StatusSegment.values)
                      FilterChip(
                        label: Text(s.label),
                        selected: a.segments.contains(s),
                        onSelected: (on) =>
                            _set((a) => a.copyWith(segments: on ? {...a.segments, s} : ({...a.segments}..remove(s)))),
                      ),
                  ],
                ),
              ),
              const _ShellIntegrationTiles(),
            ],

            section('Keys'),
            SwitchListTile(
              title: const Text('Key toolbar'),
              subtitle: const Text('Esc, Tab, Ctrl, Alt, arrows… (turn off with a hardware keyboard)'),
              value: a.keyToolbar,
              onChanged: (v) => _set((a) => a.copyWith(keyToolbar: v)),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _previewBar(TerminalAppearance a, TerminalTheme theme) => TerminalStatusBar(
    data: const StatusBarData(
      host: 'demo@laptop',
      cwd: '/home/demo/code/payments-api',
      git: GitStatus(branch: 'main', ahead: 1, changes: 2),
    ),
    appearance: a,
    theme: theme,
  );
}

class _ThemeCard extends StatelessWidget {
  const _ThemeCard({required this.label, required this.theme, required this.selected, required this.onTap});

  final String label;
  final TerminalTheme theme;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          width: 108,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: theme.background,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(width: selected ? 3 : 1, color: selected ? scheme.primary : scheme.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: theme.foreground, fontSize: 12, fontWeight: FontWeight.w600),
              ),
              Row(
                children: [
                  for (final c in [theme.red, theme.green, theme.yellow, theme.blue, theme.magenta, theme.cyan])
                    Expanded(
                      child: Container(height: 8, margin: const EdgeInsets.only(right: 2), color: c),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShellIntegrationTiles extends ConsumerWidget {
  const _ShellIntegrationTiles();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final on = ref.watch(terminalAppearanceProvider.select((a) => a.shellIntegration));
    return Column(
      children: [
        SwitchListTile(
          title: const Text('Shell integration'),
          subtitle: const Text(
            'After login, types a one-line hook (bash, zsh, fish) so the shell reports its folder. '
            'Takes effect on the next connect.',
          ),
          value: on,
          onChanged: (v) =>
              ref.read(terminalAppearanceProvider.notifier).update((a) => a.copyWith(shellIntegration: v)),
        ),
        ListTile(
          leading: const Icon(Icons.content_copy),
          title: const Text('Copy hook for your rc file'),
          subtitle: const Text(
            'Permanent alternative: no typing on connect. Shells that already report their folder (OSC 7) '
            'need nothing.',
          ),
          onTap: () => showShellIntegrationSheet(context),
        ),
      ],
    );
  }
}

/// Explains how the status bar learns the shell's folder, with the hook to
/// copy and the switch to type it automatically.
Future<void> showShellIntegrationSheet(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  useRootNavigator: true,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (sheet) => DraggableScrollableSheet(
    expand: false,
    initialChildSize: 0.6,
    maxChildSize: 0.95,
    builder: (sheet, scroll) => Consumer(
      builder: (context, ref, _) {
        final theme = Theme.of(context);
        Widget snippet(String title, String code) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(title, style: theme.textTheme.labelLarge)),
                  IconButton(
                    tooltip: 'Copy',
                    icon: const Icon(Icons.copy, size: 18),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: code));
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied')));
                    },
                  ),
                ],
              ),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SelectableText(code, style: TextStyle(fontFamily: CodeFont.jetBrainsMono.family, fontSize: 12)),
              ),
            ],
          ),
        );
        return ListView(
          controller: scroll,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text('Show the git branch', style: theme.textTheme.titleMedium),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                'The status bar needs to know which folder the shell is in. Shells can report it before each '
                'prompt (OSC 7); the branch is then read with git on a separate SSH channel, so nothing else is '
                'typed into your shell.',
              ),
            ),
            SwitchListTile(
              title: const Text('Type the hook on connect'),
              value: ref.watch(terminalAppearanceProvider.select((a) => a.shellIntegration)),
              onChanged: (v) =>
                  ref.read(terminalAppearanceProvider.notifier).update((a) => a.copyWith(shellIntegration: v)),
            ),
            const Padding(padding: EdgeInsets.fromLTRB(16, 4, 16, 0), child: Text('Or add it to your shell once:')),
            snippet('~/.bashrc or ~/.zshrc', shellHookSnippet(fish: false)),
            snippet('~/.config/fish/config.fish', shellHookSnippet(fish: true)),
            const SizedBox(height: 24),
          ],
        );
      },
    ),
  ),
);

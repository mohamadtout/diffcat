import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/layout/readable_width.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/code_fonts.dart';
import '../../core/widgets/color_picker.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/text_input_dialog.dart';
import '../../data/github/models/models.dart';
import 'diff_colors.dart';
import 'diff_settings.dart';
import 'diff_view.dart';

const _sample = [
  GhFileChange(
    filename: 'internal/webhooks/retry.go',
    status: FileChangeStatus.modified,
    additions: 4,
    deletions: 2,
    patch:
        '@@ -12,7 +12,9 @@ type Retrier struct {\n'
        ' \tclient  *http.Client\n'
        '-\tdelay   time.Duration\n'
        '+\tbase    time.Duration\n'
        '+\tmax     time.Duration\n'
        ' \tretries int\n'
        ' }\n'
        '-func (r *Retrier) wait() time.Duration { return r.delay }\n'
        '+// backoff doubles the wait after each failed attempt.\n'
        '+func (r *Retrier) backoff(n int) time.Duration { return min(r.base<<n, r.max) }',
  ),
];

/// Settings → Code view: font, size, wrapping, full files and diff colors,
/// with a live sample diff.
class CodeViewSettingsScreen extends ConsumerStatefulWidget {
  const CodeViewSettingsScreen({super.key});

  @override
  ConsumerState<CodeViewSettingsScreen> createState() => _CodeViewSettingsScreenState();
}

class _CodeViewSettingsScreenState extends ConsumerState<CodeViewSettingsScreen> {
  /// Which mode's colors are being edited (defaults to the current one).
  bool? _editDark;

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(diffSettingsProvider);
    final colors = ref.watch(diffColorsProvider);
    final notifier = ref.read(diffSettingsProvider.notifier);
    final theme = Theme.of(context);
    final dark = _editDark ?? theme.brightness == Brightness.dark;
    final effective = dark ? colors.darkColors : colors.lightColors;
    final overrides = colors.overrides(dark: dark);
    final palettes = ref.read(diffColorsProvider.notifier);
    final selected = colors.preset;
    final isProfile = colors.editingProfile;

    // The preview shows the mode being edited, even if the app is in the other.
    final previewTheme = (dark ? AppTheme.dark : AppTheme.light)(diff: effective);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Code view'),
        actions: [
          TextButton(
            onPressed: () {
              final hadHidden = ref.read(diffColorsProvider).hidden.isNotEmpty;
              ref.read(diffColorsProvider.notifier).reset();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'GitHub colors${hadHidden ? ', deleted presets restored' : ''}. Your profiles are kept.',
                  ),
                ),
              );
            },
            child: const Text('Reset colors'),
          ),
        ],
      ),
      body: ReadableWidth(
        builder: (sides) => ListView(
          padding: sides,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Theme(
                  data: previewTheme,
                  child: const Material(
                    child: SizedBox(
                      height: 250,
                      child: DiffView(
                        repo: (owner: 'demo', name: 'preview'),
                        files: _sample,
                        fileRef: 'preview',
                        preview: true,
                      ),
                    ),
                  ),
                ),
              ),
            ),

            const SectionHeader('Font'),
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
                      selected: settings.font == f,
                      onSelected: (_) => notifier.setFont(f),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  const SizedBox(width: 92, child: Text('Size')),
                  Expanded(
                    child: Slider(
                      value: settings.fontSize,
                      min: DiffSettings.minFontSize,
                      max: DiffSettings.maxFontSize,
                      divisions: ((DiffSettings.maxFontSize - DiffSettings.minFontSize) * 2).round(),
                      onChanged: notifier.setFontSize,
                    ),
                  ),
                  SizedBox(width: 44, child: Text(settings.fontSize.toStringAsFixed(1), textAlign: TextAlign.end)),
                ],
              ),
            ),
            SwitchListTile(
              title: const Text('Wrap long lines'),
              value: settings.wrap,
              onChanged: (_) => notifier.toggleWrap(),
            ),
            SwitchListTile(
              title: const Text('Syntax highlighting'),
              subtitle: const Text('Colors code by language, and marks the exact words that changed in a line'),
              value: settings.syntax,
              onChanged: notifier.setSyntax,
            ),
            SwitchListTile(
              title: const Text('Show full files'),
              subtitle: const Text(
                'Changed files show whole, with changes in place, instead of only the changed parts. '
                'Each file costs one more GitHub request when it comes into view. Switch per file from its menu.',
              ),
              value: settings.fullFile,
              onChanged: notifier.setFullFile,
            ),

            const SectionHeader('Diff colors'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final p in colors.available)
                    ChoiceChip(
                      avatar: _Dots(dark ? p.dark : p.light),
                      label: Text(p.label),
                      selected: selected.id == p.id,
                      onSelected: (_) => palettes.setPalette(p.id),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Wrap(
                children: [
                  TextButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text('New profile'),
                    onPressed: () async {
                      final name = await _askName(context, title: 'New color profile', initial: 'My colors');
                      if (name != null) palettes.createProfile(name);
                    },
                  ),
                  if (isProfile)
                    TextButton.icon(
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('Rename'),
                      onPressed: () async {
                        final name = await _askName(context, title: 'Rename profile', initial: selected.label);
                        if (name != null) palettes.renameProfile(selected.id, name);
                      },
                    ),
                  if (colors.available.length > 1)
                    TextButton.icon(
                      icon: const Icon(Icons.delete_outline),
                      label: Text('Delete ${selected.label}'),
                      onPressed: () => _delete(context, palettes, selected, isProfile: isProfile),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
              child: Text(
                isProfile
                    ? 'Your profile: color changes are saved to it.'
                    : 'Changes to a preset are dropped when you switch palettes. '
                          'Keep them with New profile.',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, icon: Icon(Icons.light_mode_outlined), label: Text('Light')),
                  ButtonSegment(value: true, icon: Icon(Icons.dark_mode_outlined), label: Text('Dark')),
                ],
                selected: {dark},
                onSelectionChanged: (s) => setState(() => _editDark = s.first),
              ),
            ),
            for (final slot in DiffColorSlot.values)
              ListTile(
                leading: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: effective[slot],
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: theme.colorScheme.outlineVariant),
                  ),
                ),
                title: Text(slot.label),
                subtitle: Text(
                  '${hexOf(effective[slot])}${!isProfile && overrides.containsKey(slot) ? ' · changed' : ''}',
                  style: TextStyle(fontFamily: AppTheme.monoFamily),
                ),
                trailing: !isProfile && overrides.containsKey(slot)
                    ? IconButton(
                        tooltip: 'Back to the palette color',
                        icon: const Icon(Icons.undo),
                        onPressed: () => palettes.setColor(slot, null, dark: dark),
                      )
                    : null,
                onTap: () async {
                  final picked = await showColorPicker(context, initial: effective[slot], title: slot.label);
                  if (picked != null) palettes.setColor(slot, picked, dark: dark);
                },
              ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

Future<void> _delete(
  BuildContext context,
  DiffColorsNotifier palettes,
  DiffPalette palette, {
  required bool isProfile,
}) async {
  if (isProfile) {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${palette.label}?'),
        content: const Text("Its light and dark colors are deleted. This can't be undone."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true) palettes.delete(palette.id);
    return;
  }
  palettes.delete(palette.id);
  ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text('${palette.label} removed. Reset colors brings it back.')));
}

Future<String?> _askName(BuildContext context, {required String title, required String initial}) => askText(
  context,
  title: title,
  action: 'Save',
  initial: initial,
  label: 'Name',
  helper: 'Starts from the colors shown, light and dark',
  maxLength: 30,
);

/// Added / removed colors of a palette, for its chip. The chip sizes its
/// avatar to the label's line height, which shrinks with smaller system text,
/// so the dots scale down to fit rather than overflow.
class _Dots extends StatelessWidget {
  const _Dots(this.c);

  final DiffColors c;

  @override
  Widget build(BuildContext context) => FittedBox(
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (i, color) in [c.addFg, c.delFg].indexed)
          Container(
            width: 8,
            height: 8,
            margin: EdgeInsets.only(left: i == 0 ? 0 : 2),
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
      ],
    ),
  );
}

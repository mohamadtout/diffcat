import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/layout/readable_width.dart';
import '../../core/theme/app_theme.dart';
import 'custom_command.dart';

/// Create, edit, reorder and delete custom command buttons.
class CommandsScreen extends ConsumerWidget {
  const CommandsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final commands = ref.watch(customCommandsProvider);
    final notifier = ref.read(customCommandsProvider.notifier);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Command buttons'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (_) async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Reset to defaults?'),
                  content: const Text('Your custom buttons will be replaced.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                    FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Reset')),
                  ],
                ),
              );
              if (ok ?? false) await notifier.resetDefaults();
            },
            itemBuilder: (_) => const [PopupMenuItem(value: 'reset', child: Text('Reset to defaults'))],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('Add button'),
        onPressed: () => _edit(context, ref, null),
      ),
      body: ReadableWidth(
        builder: (sides) => ReorderableListView.builder(
          padding: sides + const EdgeInsets.only(bottom: 96),
          itemCount: commands.length,
          onReorderItem: notifier.move,
          header: const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Text(
              'API buttons run in the repo console. SSH buttons type into the '
              'terminal using key notation: <enter> <esc> <tab> <up> <c-c> … '
              'Drag to reorder.',
            ),
          ),
          itemBuilder: (context, i) {
            final c = commands[i];
            return ListTile(
              key: ValueKey(c.id),
              leading: Icon(c.target == CommandTarget.api ? Icons.cloud_outlined : Icons.terminal),
              title: Text(c.label),
              subtitle: Text(c.command, style: TextStyle(fontFamily: AppTheme.monoFamily, fontSize: 12)),
              onTap: () => _edit(context, ref, c),
              trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => notifier.remove(c.id)),
            );
          },
        ),
      ),
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref, CustomCommand? existing) async {
    final result = await showDialog<CustomCommand>(
      context: context,
      builder: (_) => _CommandDialog(existing: existing),
    );
    if (result != null) await ref.read(customCommandsProvider.notifier).upsert(result);
  }
}

class _CommandDialog extends StatefulWidget {
  const _CommandDialog({this.existing});
  final CustomCommand? existing;

  @override
  State<_CommandDialog> createState() => _CommandDialogState();
}

class _CommandDialogState extends State<_CommandDialog> {
  late final _label = TextEditingController(text: widget.existing?.label);
  late final _command = TextEditingController(text: widget.existing?.command);
  late CommandTarget _target = widget.existing?.target ?? CommandTarget.ssh;

  @override
  void dispose() {
    _label.dispose();
    _command.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.existing == null ? 'New button' : 'Edit button'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SegmentedButton<CommandTarget>(
            segments: const [
              ButtonSegment(value: CommandTarget.ssh, icon: Icon(Icons.terminal), label: Text('SSH')),
              ButtonSegment(value: CommandTarget.api, icon: Icon(Icons.cloud_outlined), label: Text('API')),
            ],
            selected: {_target},
            onSelectionChanged: (s) => setState(() => _target = s.first),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _label,
            decoration: const InputDecoration(labelText: 'Label'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _command,
            style: TextStyle(fontFamily: AppTheme.monoFamily),
            autocorrect: false,
            enableSuggestions: false,
            maxLines: 3,
            minLines: 1,
            decoration: InputDecoration(
              labelText: 'Command',
              helperMaxLines: 3,
              helperText: _target == CommandTarget.ssh
                  ? 'Typed into the shell. End with <enter> to run. e.g. cd ~/code/app && lazygit<enter>'
                  : 'Console command, e.g. log -n 50 -- lib/  or  since v1.2.0',
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(
        onPressed: () {
          if (_label.text.trim().isEmpty || _command.text.isEmpty) return;
          Navigator.pop(
            context,
            CustomCommand(
              id: widget.existing?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
              label: _label.text.trim(),
              command: _command.text,
              target: _target,
            ),
          );
        },
        child: const Text('Save'),
      ),
    ],
  );
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/routing/routes.dart';
import '../../core/theme/app_theme.dart';
import '../../data/github/models/models.dart';
import '../commands/custom_command.dart';
import 'console_controller.dart';
import 'console_models.dart';

/// Terminal-like console that runs git-style commands via the GitHub API.
class ConsoleTab extends ConsumerStatefulWidget {
  const ConsoleTab({super.key, required this.repo, required this.gitRef});

  final RepoRef repo;
  final String gitRef;

  @override
  ConsumerState<ConsoleTab> createState() => _ConsoleTabState();
}

class _ConsoleTabState extends ConsumerState<ConsoleTab> {
  final _input = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();
  int _historyPos = -1;

  @override
  void dispose() {
    _input.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _run(String line) async {
    _input.clear();
    _historyPos = -1;
    final route = await ref.read(consoleProvider(widget.repo).notifier).run(line, gitRef: widget.gitRef);
    if (route != null && mounted) unawaited(context.push(route));
  }

  void _recall(int delta) {
    final history = ref.read(consoleProvider(widget.repo).notifier).history;
    if (history.isEmpty) return;
    _historyPos = _historyPos == -1 ? (delta < 0 ? history.length - 1 : -1) : (_historyPos + delta);
    if (_historyPos < 0 || _historyPos >= history.length) {
      _historyPos = -1;
      _input.clear();
      return;
    }
    _input.text = history[_historyPos];
    _input.selection = TextSelection.collapsed(offset: _input.text.length);
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final entries = ref.watch(consoleProvider(widget.repo));
    ref.listen(consoleProvider(widget.repo), (_, _) => _scrollToEnd());
    final buttons = ref.watch(customCommandsProvider).where((c) => c.target == CommandTarget.api).toList();
    final scheme = Theme.of(context).colorScheme;
    final mono = AppTheme.mono(context, size: 12.5);

    return Column(
      children: [
        Expanded(
          child: entries.isEmpty
              ? _Intro(gitRef: widget.gitRef, onRun: _run)
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.all(12),
                  itemCount: entries.length,
                  itemBuilder: (context, i) => _EntryView(entry: entries[i], mono: mono),
                ),
        ),
        if (buttons.isNotEmpty)
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              children: [
                for (final b in buttons)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                    child: ActionChip(label: Text(b.label), tooltip: b.command, onPressed: () => _run(b.command)),
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                  child: ActionChip(
                    avatar: const Icon(Icons.tune, size: 16),
                    label: const Text('Edit'),
                    onPressed: () => context.push(Routes.commands),
                  ),
                ),
              ],
            ),
          ),
        Material(
          color: scheme.surfaceContainer,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
              child: Row(
                children: [
                  Text('❯', style: mono.copyWith(color: scheme.primary, fontSize: 16)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Focus(
                      onKeyEvent: (_, e) {
                        if (e is! KeyDownEvent) return KeyEventResult.ignored;
                        if (e.logicalKey == LogicalKeyboardKey.arrowUp) {
                          _recall(-1);
                          return KeyEventResult.handled;
                        }
                        if (e.logicalKey == LogicalKeyboardKey.arrowDown) {
                          _recall(1);
                          return KeyEventResult.handled;
                        }
                        return KeyEventResult.ignored;
                      },
                      child: TextField(
                        controller: _input,
                        focusNode: _focus,
                        style: mono,
                        autocorrect: false,
                        enableSuggestions: false,
                        textInputAction: TextInputAction.send,
                        decoration: InputDecoration(
                          hintText: 'git log -n 5   (type help)',
                          border: InputBorder.none,
                          hintStyle: mono.copyWith(color: scheme.outline),
                        ),
                        onSubmitted: (v) {
                          _run(v);
                          _focus.requestFocus();
                        },
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Previous command',
                    icon: const Icon(Icons.keyboard_arrow_up),
                    onPressed: () => _recall(-1),
                  ),
                  IconButton(tooltip: 'Run', icon: const Icon(Icons.send), onPressed: () => _run(_input.text)),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Intro extends StatelessWidget {
  const _Intro({required this.gitRef, required this.onRun});

  final String gitRef;
  final ValueChanged<String> onRun;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      Text('API console', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      Text(
        'Run git-style commands straight against GitHub — nothing is cloned. '
        'HEAD is "$gitRef". For a real shell (lazygit, arbitrary commands) use '
        'the Terminal tab with an SSH host.',
      ),
      const SizedBox(height: 16),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final cmd in ['help', 'log -n 10', 'show HEAD', 'diff HEAD~5..HEAD', 'prs'])
            ActionChip(label: Text(cmd), onPressed: () => onRun(cmd)),
        ],
      ),
    ],
  );
}

class _EntryView extends StatelessWidget {
  const _EntryView({required this.entry, required this.mono});

  final ConsoleEntry entry;
  final TextStyle mono;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '❯ ',
                  style: mono.copyWith(color: scheme.primary),
                ),
                TextSpan(
                  text: entry.input,
                  style: mono.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          if (entry.running)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: SizedBox(width: 80, child: LinearProgressIndicator()),
            ),
          for (final line in entry.output) _LineView(line: line, mono: mono),
        ],
      ),
    );
  }
}

class _LineView extends StatelessWidget {
  const _LineView({required this.line, required this.mono});

  final ConsoleLine line;
  final TextStyle mono;

  @override
  Widget build(BuildContext context) {
    final c = DiffColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    TextStyle styleFor(SpanStyle s) => switch (s) {
      SpanStyle.normal => mono,
      SpanStyle.dim => mono.copyWith(color: scheme.outline),
      SpanStyle.add => mono.copyWith(color: c.addFg),
      SpanStyle.del => mono.copyWith(color: c.delFg),
      SpanStyle.accent => mono.copyWith(color: c.hunkFg),
      SpanStyle.error => mono.copyWith(color: scheme.error),
      SpanStyle.heading => mono.copyWith(fontWeight: FontWeight.bold),
      SpanStyle.sha => mono.copyWith(color: Colors.amber.shade700),
    };
    final text = Text.rich(
      TextSpan(
        children: [for (final s in line.spans) TextSpan(text: s.text, style: styleFor(s.style))],
      ),
    );
    if (line.route == null) return text;
    return InkWell(
      onTap: () => context.push(line.route!),
      onLongPress: () => Clipboard.setData(ClipboardData(text: line.plain)),
      child: Padding(padding: const EdgeInsets.symmetric(vertical: 1), child: text),
    );
  }
}

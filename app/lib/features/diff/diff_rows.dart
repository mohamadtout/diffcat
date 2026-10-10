part of 'diff_view.dart';

// The rows DiffView builds: toolbar, file and hunk headers, and code lines.

class _Metrics {
  const _Metrics({required this.mono, required this.gutter, required this.sign, required this.wrap});

  final TextStyle mono;
  final double gutter;
  final double sign;
  final bool wrap;
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.files,
    required this.current,
    required this.wrap,
    required this.onJump,
    required this.onToggleWrap,
    required this.onTextSize,
    required this.onExpandAll,
    required this.onCollapseAll,
    required this.fullFiles,
    required this.onToggleFullFiles,
  });

  final bool fullFiles;
  final VoidCallback onToggleFullFiles;
  final List<GhFileChange> files;
  final ValueNotifier<int> current;
  final bool wrap;
  final ValueChanged<int> onJump;
  final VoidCallback onToggleWrap;
  final VoidCallback onTextSize;
  final VoidCallback onExpandAll;
  final VoidCallback onCollapseAll;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainer,
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: () => _showFilePicker(context),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                child: ValueListenableBuilder<int>(
                  valueListenable: current,
                  builder: (context, i, _) {
                    final f = files[i.clamp(0, files.length - 1)];
                    return Row(
                      children: [
                        Text('${i + 1}/${files.length}', style: theme.textTheme.labelMedium),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            f.filename,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(fontFamily: AppTheme.monoFamily),
                          ),
                        ),
                        const Icon(Icons.arrow_drop_down),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: wrap ? 'Disable line wrap' : 'Wrap long lines',
            isSelected: wrap,
            icon: const Icon(Icons.wrap_text),
            onPressed: onToggleWrap,
          ),
          PopupMenuButton<String>(
            onSelected: (v) => switch (v) {
              'expand' => onExpandAll(),
              'collapse' => onCollapseAll(),
              'textSize' => onTextSize(),
              'full' => onToggleFullFiles(),
              _ => null,
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'expand', child: Text('Expand all files')),
              const PopupMenuItem(value: 'collapse', child: Text('Collapse all files')),
              CheckedPopupMenuItem(value: 'full', checked: fullFiles, child: const Text('Full files')),
              const PopupMenuDivider(),
              const PopupMenuItem(value: 'textSize', child: Text('Text size…')),
            ],
          ),
        ],
      ),
    );
  }

  void _showFilePicker(BuildContext context) {
    final adds = files.fold<int>(0, (s, f) => s + f.additions);
    final dels = files.fold<int>(0, (s, f) => s + f.deletions);
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true, // cover the shell navigation bar/rail
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.95,
        builder: (ctx, scroll) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Text('${files.length} files changed', style: Theme.of(ctx).textTheme.titleSmall),
                  const Spacer(),
                  LineCounts(additions: adds, deletions: dels),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                controller: scroll,
                itemCount: files.length,
                itemBuilder: (ctx, i) {
                  final f = files[i];
                  return ListTile(
                    dense: true,
                    leading: StatusBadge(f.status),
                    title: Text(f.basename, overflow: TextOverflow.ellipsis),
                    subtitle: f.directory.isEmpty ? null : Text(f.directory, overflow: TextOverflow.ellipsis),
                    trailing: LineCounts(additions: f.additions, deletions: f.deletions),
                    onTap: () {
                      Navigator.pop(ctx);
                      onJump(i);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FileHeader extends StatelessWidget {
  const _FileHeader({
    required this.file,
    required this.collapsed,
    required this.focused,
    required this.onToggle,
    required this.onHistory,
    this.onOpenFile,
    this.actions = true,
    this.full,
    this.onToggleFull,
    this.onBuilt,
  });

  final bool actions;

  /// Whether the file shows whole; null when it can't.
  final bool? full;
  final VoidCallback? onToggleFull;

  /// Called after each build (the row is on or near the screen).
  final VoidCallback? onBuilt;
  final GhFileChange file;
  final bool collapsed;
  final bool focused;
  final VoidCallback onToggle;
  final VoidCallback? onOpenFile;
  final VoidCallback onHistory;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    if (onBuilt case final built?) WidgetsBinding.instance.addPostFrameCallback((_) => built());
    return Material(
      color: scheme.surfaceContainerHigh,
      shape: Border(
        left: BorderSide(color: focused ? scheme.primary : Colors.transparent, width: 3),
        top: BorderSide(color: scheme.outlineVariant),
        bottom: BorderSide(color: scheme.outlineVariant),
      ),
      child: InkWell(
        onTap: onToggle,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 6, 0, 6),
          child: Row(
            children: [
              Icon(collapsed ? Icons.chevron_right : Icons.expand_more, size: 20),
              const SizedBox(width: 4),
              StatusBadge(file.status),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      file.basename,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        fontFamily: AppTheme.monoFamily,
                      ),
                    ),
                    if (file.directory.isNotEmpty)
                      Text(
                        file.directory,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(color: scheme.outline),
                      ),
                    if (file.previousFilename != null)
                      Text(
                        'from ${file.previousFilename}',
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(color: scheme.outline),
                      ),
                  ],
                ),
              ),
              LineCounts(additions: file.additions, deletions: file.deletions),
              if (!actions)
                const SizedBox(width: 12)
              else
                PopupMenuButton<String>(
                  tooltip: 'File actions',
                  onSelected: (v) {
                    switch (v) {
                      case 'open':
                        onOpenFile?.call();
                      case 'history':
                        onHistory();
                      case 'full':
                        onToggleFull?.call();
                      case 'path':
                        Clipboard.setData(ClipboardData(text: file.filename));
                      case 'patch':
                        Clipboard.setData(ClipboardData(text: file.patch ?? ''));
                    }
                  },
                  itemBuilder: (_) => [
                    if (full != null)
                      PopupMenuItem(value: 'full', child: Text(full! ? 'Show changes only' : 'Show full file')),
                    if (onOpenFile != null) const PopupMenuItem(value: 'open', child: Text('View file')),
                    const PopupMenuItem(value: 'history', child: Text('File history')),
                    const PopupMenuItem(value: 'path', child: Text('Copy path')),
                    if (file.patch != null) const PopupMenuItem(value: 'patch', child: Text('Copy patch')),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HunkHeader extends StatelessWidget {
  const _HunkHeader({required this.header, required this.mono});

  final String header;
  final TextStyle mono;

  @override
  Widget build(BuildContext context) {
    final c = DiffColors.of(context);
    return Container(
      color: c.hunkBg,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Text(
        header,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: mono.copyWith(color: c.hunkFg),
      ),
    );
  }
}

class _LineView extends StatelessWidget {
  const _LineView({
    required this.line,
    required this.m,
    required this.h,
    this.segs,
    this.changed = const [],
    this.onTap,
  });

  final VoidCallback? onTap;

  final DiffLine line;

  /// Syntax-highlighted pieces, or null for plain text.
  final List<HlSeg>? segs;

  /// Words that changed against the paired removed/added line.
  final List<Span> changed;
  final _Metrics m;
  final ValueListenable<double> h;

  @override
  Widget build(BuildContext context) {
    final c = DiffColors.of(context);
    final (bg, sign, signColor) = switch (line.kind) {
      DiffLineKind.add => (c.addBg, '+', c.addFg),
      DiffLineKind.delete => (c.delBg, '-', c.delFg),
      _ => (null, ' ', c.gutter),
    };
    final gutterStyle = m.mono.copyWith(color: c.gutter);
    final isMeta = line.kind == DiffLineKind.noNewline;
    final text = line.text.replaceAll('\t', '    ');
    final codeStyle = isMeta ? m.mono.copyWith(color: c.gutter, fontStyle: FontStyle.italic) : m.mono;
    final rich = isMeta || (segs == null && changed.isEmpty)
        ? null
        : codeSpan(
            lineRuns(segs ?? [HlSeg(line.text)], changed),
            codeStyle,
            syntaxTheme(context),
            changedBg: (line.kind == DiffLineKind.delete ? c.delFg : c.addFg).withValues(alpha: 0.28),
          );
    Text textWidget({bool wrap = true}) => rich == null
        ? Text(text, style: codeStyle, softWrap: wrap, overflow: wrap ? null : TextOverflow.visible)
        : Text.rich(rich, softWrap: wrap, overflow: wrap ? null : TextOverflow.visible);

    final Widget code = m.wrap
        ? textWidget()
        : ClipRect(
            child: ValueListenableBuilder<double>(
              valueListenable: h,
              builder: (context, dx, child) => Transform.translate(offset: Offset(-dx, 0), child: child),
              child: textWidget(wrap: false),
            ),
          );

    return GestureDetector(
      onTap: onTap,
      onLongPress: () {
        Clipboard.setData(ClipboardData(text: line.text));
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text('Line copied')));
      },
      child: Container(
        color: bg,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: m.gutter,
              child: Text(line.oldNo?.toString() ?? '', textAlign: TextAlign.right, style: gutterStyle),
            ),
            SizedBox(
              width: m.gutter,
              child: Text(line.newNo?.toString() ?? '', textAlign: TextAlign.right, style: gutterStyle),
            ),
            SizedBox(
              width: m.sign,
              child: Text(
                sign,
                textAlign: TextAlign.center,
                style: m.mono.copyWith(color: signColor),
              ),
            ),
            Expanded(child: code),
          ],
        ),
      ),
    );
  }
}

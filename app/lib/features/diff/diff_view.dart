import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

import '../../core/routing/routes.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/text_size_sheet.dart';
import '../../data/github/models/models.dart';
import 'diff_document.dart';
import 'diff_parser.dart';
import 'diff_settings.dart';

/// Diffs with more changed lines than this start collapsed.
const _autoCollapseLines = 1200;

/// Scrollable, lazily-built multi-file diff.
///
/// - One sliver list for every line of every file (fast on huge commits).
/// - No-wrap mode pans code horizontally while line numbers stay pinned.
/// - Toolbar shows the file currently on screen; tap it to jump to any file.
class DiffView extends ConsumerStatefulWidget {
  const DiffView({
    super.key,
    required this.repo,
    required this.files,
    required this.fileRef,
    this.focusPath,
    this.header,
  });

  final RepoRef repo;
  final List<GhFileChange> files;

  /// Ref at which the new side of each file exists (commit / head sha).
  final String fileRef;

  /// File to scroll to and highlight on first build.
  final String? focusPath;

  /// Scrolls away with the content (commit message, PR summary…).
  final Widget? header;

  @override
  ConsumerState<DiffView> createState() => _DiffViewState();
}

class _DiffViewState extends ConsumerState<DiffView> with SingleTickerProviderStateMixin {
  final _scroll = ScrollController();
  final _list = ListController();
  final _currentFile = ValueNotifier<int>(0);
  late final AnimationController _h = AnimationController.unbounded(vsync: this);
  double _maxH = 0;

  late List<List<DiffHunk>?> _parsed;
  final Set<int> _collapsed = {};
  late DiffDocument _doc;
  int? _focusIndex;

  @override
  void initState() {
    super.initState();
    _prepare();
    _scroll.addListener(_onScroll);
    _h.addListener(_clampH);
    if (_focusIndex != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _jumpTo(_focusIndex!));
    }
  }

  @override
  void didUpdateWidget(covariant DiffView old) {
    super.didUpdateWidget(old);
    if (!identical(old.files, widget.files)) {
      _collapsed.clear();
      _prepare();
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    _list.dispose();
    _currentFile.dispose();
    _h.dispose();
    super.dispose();
  }

  void _prepare() {
    final files = widget.files;
    _parsed = [for (final f in files) f.patch == null ? null : parsePatch(f.patch!)];
    final focus = widget.focusPath;
    _focusIndex = focus == null ? null : files.indexWhere((f) => f.filename == focus || f.previousFilename == focus);
    if (_focusIndex == -1) _focusIndex = null;
    for (var i = 0; i < files.length; i++) {
      if (i != _focusIndex && files[i].additions + files[i].deletions > _autoCollapseLines) {
        _collapsed.add(i);
      }
    }
    _rebuildDoc();
  }

  void _rebuildDoc() {
    _doc = DiffDocument.build(widget.files, collapsed: _collapsed, parsed: _parsed);
  }

  void _onScroll() {
    if (!_list.isAttached) return;
    final range = _list.visibleRange;
    if (range == null || _doc.rows.isEmpty) return;
    final idx = range.$1.clamp(0, _doc.rows.length - 1);
    _currentFile.value = _doc.rows[idx].fileIndex;
  }

  void _clampH() {
    final v = _h.value;
    if (v < 0 || v > _maxH) {
      _h.stop();
      _h.value = v.clamp(0, _maxH);
    }
  }

  void _jumpTo(int fileIndex) {
    if (!_list.isAttached || fileIndex >= _doc.headerIndex.length) return;
    _list.jumpToItem(index: _doc.headerIndex[fileIndex], scrollController: _scroll, alignment: 0);
    _currentFile.value = fileIndex;
  }

  void _toggle(int i) => setState(() {
    _collapsed.contains(i) ? _collapsed.remove(i) : _collapsed.add(i);
    _rebuildDoc();
  });

  void _setAll({required bool collapsed}) => setState(() {
    _collapsed.clear();
    if (collapsed) _collapsed.addAll(List.generate(widget.files.length, (i) => i));
    _rebuildDoc();
  });

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(diffSettingsProvider);
    if (widget.files.isEmpty) {
      return CustomScrollView(
        slivers: [
          if (widget.header != null) SliverToBoxAdapter(child: widget.header),
          const SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyView(icon: Icons.difference_outlined, message: 'No file changes.'),
          ),
        ],
      );
    }
    final mono = AppTheme.mono(context, size: settings.fontSize);
    final charW = _charWidth(mono);
    final digits = math.max(3, _maxLineNo().toString().length);
    final metrics = _Metrics(mono: mono, gutter: digits * charW + 10, sign: charW + 6, wrap: settings.wrap);

    return Column(
      children: [
        _Toolbar(
          files: widget.files,
          current: _currentFile,
          wrap: settings.wrap,
          onJump: _jumpTo,
          onToggleWrap: () => ref.read(diffSettingsProvider.notifier).toggleWrap(),
          onTextSize: () => showTextSizeSheet(
            context,
            value: settings.fontSize,
            min: DiffSettings.minFontSize,
            max: DiffSettings.maxFontSize,
            onChanged: ref.read(diffSettingsProvider.notifier).setFontSize,
          ),
          onExpandAll: () => _setAll(collapsed: false),
          onCollapseAll: () => _setAll(collapsed: true),
        ),
        const Divider(height: 1),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final codeViewport = constraints.maxWidth - metrics.gutter * 2 - metrics.sign;
              _maxH = settings.wrap ? 0 : math.max(0, _doc.maxLineLength * charW + 24 - codeViewport);
              if (_h.value > _maxH) {
                // Never mutate listenables during layout; fix up after the frame.
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted && _h.value > _maxH) _h.value = _maxH;
                });
              }

              Widget view = Scrollbar(
                controller: _scroll,
                interactive: true,
                child: CustomScrollView(
                  controller: _scroll,
                  slivers: [
                    if (widget.header != null) SliverToBoxAdapter(child: widget.header),
                    SuperSliverList.builder(
                      listController: _list,
                      itemCount: _doc.rows.length,
                      itemBuilder: (context, i) => _buildRow(_doc.rows[i], metrics),
                    ),
                    SliverToBoxAdapter(child: SizedBox(height: 48 + MediaQuery.paddingOf(context).bottom)),
                  ],
                ),
              );
              if (_maxH > 0) {
                view = GestureDetector(
                  onHorizontalDragUpdate: (d) => _h.value = (_h.value - d.delta.dx).clamp(0, _maxH),
                  onHorizontalDragEnd: (d) =>
                      _h.animateWith(FrictionSimulation(0.05, _h.value, -d.velocity.pixelsPerSecond.dx)),
                  child: view,
                );
              }
              return view;
            },
          ),
        ),
      ],
    );
  }

  int _maxLineNo() {
    var max = 0;
    for (final h in _parsed) {
      if (h == null || h.isEmpty) continue;
      final last = h.last;
      max = math.max(max, last.oldStart + last.lines.length);
      max = math.max(max, last.newStart + last.lines.length);
    }
    return max;
  }

  double _charWidth(TextStyle style) {
    final tp = TextPainter(
      text: TextSpan(text: 'MMMMMMMMMM', style: style),
      textDirection: TextDirection.ltr,
      // Same scaling as the Text widgets it sizes (system text size setting).
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final w = tp.width / 10;
    tp.dispose();
    return w;
  }

  Widget _buildRow(DiffRow row, _Metrics m) => switch (row) {
    FileHeaderRow(:final fileIndex, :final file, :final collapsed) => _FileHeader(
      file: file,
      collapsed: collapsed,
      focused: fileIndex == _focusIndex,
      onToggle: () => _toggle(fileIndex),
      onOpenFile: file.status == FileChangeStatus.removed
          ? null
          : () => context.push(Routes.file(widget.repo, file.filename, widget.fileRef)),
      onHistory: () => context.push(Routes.history(widget.repo, file.filename, widget.fileRef)),
    ),
    HunkHeaderRow(:final header) => _HunkHeader(header: header, mono: m.mono),
    LineRow(:final line) => _LineView(line: line, m: m, h: _h),
    NoticeRow(:final message) => Padding(
      padding: const EdgeInsets.all(16),
      child: Text(
        message,
        style: TextStyle(fontStyle: FontStyle.italic, color: Theme.of(context).colorScheme.outline),
      ),
    ),
    FileGapRow() => const SizedBox(height: 12),
  };
}

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
  });

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
              _ => null,
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'expand', child: Text('Expand all files')),
              PopupMenuItem(value: 'collapse', child: Text('Collapse all files')),
              PopupMenuDivider(),
              PopupMenuItem(value: 'textSize', child: Text('Text size…')),
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
  });

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
              PopupMenuButton<String>(
                tooltip: 'File actions',
                onSelected: (v) {
                  switch (v) {
                    case 'open':
                      onOpenFile?.call();
                    case 'history':
                      onHistory();
                    case 'path':
                      Clipboard.setData(ClipboardData(text: file.filename));
                    case 'patch':
                      Clipboard.setData(ClipboardData(text: file.patch ?? ''));
                  }
                },
                itemBuilder: (_) => [
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
  const _LineView({required this.line, required this.m, required this.h});

  final DiffLine line;
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

    final Widget code = m.wrap
        ? Text(text, style: codeStyle)
        : ClipRect(
            child: ValueListenableBuilder<double>(
              valueListenable: h,
              builder: (context, dx, child) => Transform.translate(offset: Offset(-dx, 0), child: child),
              child: Text(text, softWrap: false, overflow: TextOverflow.visible, style: codeStyle),
            ),
          );

    return GestureDetector(
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

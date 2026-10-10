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
import '../auth/auth_controller.dart';
import 'diff_document.dart';
import 'diff_parser.dart';
import 'diff_settings.dart';
import 'syntax.dart';
import 'syntax_style.dart';

part 'diff_rows.dart';

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
    this.preview = false,
    this.onLineTap,
    this.lineFooter,
  });

  final RepoRef repo;
  final List<GhFileChange> files;

  /// Ref at which the new side of each file exists (commit / head sha).
  final String fileRef;

  /// File to scroll to and highlight on first build.
  final String? focusPath;

  /// Scrolls away with the content (commit message, PR summary…).
  final Widget? header;

  /// A sample in settings: no toolbar, no file actions, no network.
  final bool preview;

  /// Tapping a code line (e.g. to comment on it in a pull request).
  final void Function(GhFileChange file, DiffLine line)? onLineTap;

  /// Shown under a line (e.g. its review comments), or null for nothing.
  final Widget? Function(GhFileChange file, DiffLine line)? lineFooter;

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

  // Syntax highlighting and word emphasis, computed per file the first time
  // one of its lines is built, and looked up per line.
  final Set<int> _prepared = {};
  var _segs = Expando<List<HlSeg>>();
  var _emph = Expando<List<Span>>();
  bool _syntax = true;
  final Set<int> _collapsed = {};
  late DiffDocument _doc;
  int? _focusIndex;

  // Full-file mode (DiffSettings.fullFile, or toggled per file).
  bool _fullDefault = false;

  /// Files toggled away from [_fullDefault].
  final Set<int> _fullToggled = {};
  final Map<int, List<DiffLine>> _full = {};
  final Set<int> _fullLoading = {};
  final Map<int, String> _fullFailed = {};

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
      _fullToggled.clear();
      _full.clear();
      _fullLoading.clear();
      _fullFailed.clear();
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
    final wanted = {
      for (var i = 0; i < widget.files.length; i++)
        if (_wantsFull(i)) i,
    };
    _doc = DiffDocument.build(
      widget.files,
      collapsed: _collapsed,
      parsed: _parsed,
      full: {for (final i in wanted) i: ?_full[i]},
      notices: {
        for (final i in wanted)
          if (_fullFailed[i] case final why?) i: why else if (!_full.containsKey(i)) i: 'Loading the full file…',
      },
    );
  }

  /// Modified files can be shown whole; added and removed ones already are.
  bool _canShowFull(int i) {
    final f = widget.files[i];
    return !widget.preview &&
        _parsed[i] != null &&
        _parsed[i]!.isNotEmpty &&
        f.status != FileChangeStatus.added &&
        f.status != FileChangeStatus.removed;
  }

  bool _wantsFull(int i) => _canShowFull(i) && (_fullDefault != _fullToggled.contains(i));

  void _toggleFull(int i) => setState(() {
    _fullToggled.contains(i) ? _fullToggled.remove(i) : _fullToggled.add(i);
    _collapsed.remove(i);
    _rebuildDoc();
  });

  /// Fetches file [i]'s content once its header is built (scrolled near), so
  /// a long diff doesn't spend a request per file up front.
  Future<void> _loadFull(int i) async {
    if (!_wantsFull(i) || _full.containsKey(i) || _fullLoading.contains(i) || _fullFailed.containsKey(i)) return;
    _fullLoading.add(i);
    final file = widget.files[i];
    final hunks = _parsed[i]!;
    String? failed;
    List<DiffLine>? lines;
    try {
      final content = await ref.read(githubApiProvider).fileContent(widget.repo, file.filename, widget.fileRef);
      lines = content.contains('\u0000') ? null : fullFileLines(content, hunks);
      if (lines == null) failed = "The file doesn't match this diff (its branch may have moved). Showing changes only.";
    } on Object catch (e) {
      failed = "Couldn't load the full file: $e";
    }
    if (!mounted || !identical(file, widget.files.elementAtOrNull(i))) return;
    setState(() {
      _fullLoading.remove(i);
      if (lines != null) _full[i] = lines;
      _prepared.remove(i);
      if (failed != null) _fullFailed[i] = failed;
      _rebuildDoc();
    });
  }

  void _onScroll() {
    if (!_list.isAttached) return;
    final range = _list.visibleRange;
    if (range == null || _doc.rows.isEmpty) return;
    final idx = range.$1.clamp(0, _doc.rows.length - 1);
    _currentFile.value = _doc.rows[idx].fileIndex;
  }

  Widget _withFooter(int file, DiffLine line, Widget lineView) {
    final footer = widget.lineFooter?.call(widget.files[file], line);
    return footer == null
        ? lineView
        : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [lineView, footer]);
  }

  List<HlSeg>? _segsFor(int file, DiffLine line) {
    if (_syntax && _prepared.add(file)) _prepareFile(file);
    return _segs[line];
  }

  void _prepareFile(int i) {
    final hunks = _parsed[i];
    if (hunks == null) return;
    final full = _full[i];
    final lines = full ?? [for (final h in hunks) ...h.lines];
    final language = languageForPath(widget.files[i].filename);
    if (language != null) {
      final hl = highlightDiffLines(lines, language);
      for (var k = 0; k < lines.length; k++) {
        _segs[lines[k]] = hl[k];
      }
    }
    for (final block in full == null ? [for (final h in hunks) h.lines] : [full]) {
      for (final e in pairedWordDiffs(block).entries) {
        _emph[block[e.key]] = e.value;
      }
    }
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
    if (settings.syntax != _syntax) {
      _syntax = settings.syntax;
      _prepared.clear();
      _segs = Expando();
      _emph = Expando();
    }
    if (settings.fullFile != _fullDefault) {
      _fullDefault = settings.fullFile;
      _fullToggled.clear();
      _rebuildDoc();
    }
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
    final mono = settings.codeStyle(context);
    final charW = _charWidth(mono);
    final digits = math.max(3, _maxLineNo().toString().length);
    final metrics = _Metrics(mono: mono, gutter: digits * charW + 10, sign: charW + 6, wrap: settings.wrap);

    return Column(
      children: [
        if (!widget.preview) ...[
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
            fullFiles: settings.fullFile,
            onToggleFullFiles: () => ref.read(diffSettingsProvider.notifier).setFullFile(!settings.fullFile),
          ),
          const Divider(height: 1),
        ],
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
    for (final lines in _full.values) {
      if (lines.isEmpty) continue;
      max = math.max(max, math.max(lines.last.oldNo ?? 0, lines.last.newNo ?? 0));
    }
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
      actions: !widget.preview,
      onToggle: () => _toggle(fileIndex),
      full: _canShowFull(fileIndex) ? _wantsFull(fileIndex) : null,
      onToggleFull: () => _toggleFull(fileIndex),
      onBuilt: collapsed || !_wantsFull(fileIndex) ? null : () => _loadFull(fileIndex),
      onOpenFile: file.status == FileChangeStatus.removed
          ? null
          : () => context.push(Routes.file(widget.repo, file.filename, widget.fileRef)),
      onHistory: () => context.push(Routes.history(widget.repo, file.filename, widget.fileRef)),
    ),
    HunkHeaderRow(:final header) => _HunkHeader(header: header, mono: m.mono),
    LineRow(:final fileIndex, :final line) => _withFooter(
      fileIndex,
      line,
      _LineView(
        line: line,
        m: m,
        h: _h,
        segs: _segsFor(fileIndex, line),
        changed: _emph[line] ?? const [],
        onTap: widget.onLineTap == null ? null : () => widget.onLineTap!(widget.files[fileIndex], line),
      ),
    ),
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

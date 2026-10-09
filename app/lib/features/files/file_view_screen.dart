import 'dart:isolate';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/routing/routes.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/async_view.dart';
import '../../data/github/models/models.dart';
import '../auth/auth_controller.dart';
import '../diff/diff_settings.dart';
import '../diff/syntax.dart';
import '../diff/syntax_style.dart';
import 'files_providers.dart';

const _imageExts = {'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp'};

class FileViewScreen extends StatelessWidget {
  const FileViewScreen({super.key, required this.repo, required this.path, required this.gitRef});

  final RepoRef repo;
  final String path;
  final String gitRef;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(path.split('/').last),
          Text(
            '$path @ ${gitRef.length == 40 ? gitRef.substring(0, 7) : gitRef}',
            style: Theme.of(context).textTheme.labelSmall,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    ),
    body: FileView(repo: repo, path: path, gitRef: gitRef, showToolbar: true),
  );
}

/// File contents with line numbers plus quick actions (history, copy).
class FileView extends ConsumerWidget {
  const FileView({super.key, required this.repo, required this.path, required this.gitRef, this.showToolbar = true});

  final RepoRef repo;
  final String path;
  final String gitRef;
  final bool showToolbar;

  bool get _isImage => _imageExts.contains(path.split('.').last.toLowerCase());

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = (repo: repo, path: path, ref: gitRef);
    final toolbar = Material(
      color: Theme.of(context).colorScheme.surfaceContainer,
      child: Row(
        children: [
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              path,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontFamily: AppTheme.monoFamily, fontSize: 12),
            ),
          ),
          TextButton.icon(
            icon: const Icon(Icons.history, size: 18),
            label: const Text('History'),
            onPressed: () => context.push(Routes.history(repo, path, gitRef)),
          ),
          IconButton(
            tooltip: 'Copy path',
            icon: const Icon(Icons.copy, size: 18),
            onPressed: () => Clipboard.setData(ClipboardData(text: path)),
          ),
          IconButton(
            tooltip: 'Wrap lines',
            isSelected: ref.watch(diffSettingsProvider).wrap,
            icon: const Icon(Icons.wrap_text, size: 18),
            onPressed: () => ref.read(diffSettingsProvider.notifier).toggleWrap(),
          ),
        ],
      ),
    );

    final Widget body;
    if (_isImage) {
      final token = ref.watch(authTokenProvider).value;
      final encoded = path.split('/').map(Uri.encodeComponent).join('/');
      body = InteractiveViewer(
        maxScale: 8,
        child: Center(
          child: Image.network(
            'https://api.github.com/repos/${repo.owner}/${repo.name}/contents/$encoded?ref=${Uri.encodeQueryComponent(gitRef)}',
            headers: {
              'Authorization': ?(token == null ? null : 'Bearer $token'),
              'Accept': 'application/vnd.github.raw+json',
            },
            errorBuilder: (_, e, _) => ErrorView(error: e),
          ),
        ),
      );
    } else {
      body = AsyncView(
        value: ref.watch(fileContentProvider(key)),
        onRetry: () => ref.invalidate(fileContentProvider(key)),
        data: (content) => content.contains('\u0000')
            ? const EmptyView(icon: Icons.memory, message: 'Binary file not shown.')
            : CodeLines(content: content, path: path),
      );
    }

    return Column(
      children: [
        if (showToolbar) ...[toolbar, const Divider(height: 1)],
        Expanded(child: body),
      ],
    );
  }
}

/// Lazily-rendered source code with a line-number gutter.
class CodeLines extends ConsumerStatefulWidget {
  const CodeLines({super.key, required this.content, this.path});

  final String content;

  /// Picks the syntax highlighting language.
  final String? path;

  @override
  ConsumerState<CodeLines> createState() => _CodeLinesState();
}

class _CodeLinesState extends ConsumerState<CodeLines> {
  // Split once per content, not on every rebuild (the text size slider
  // rebuilds on every tick, and files can have tens of thousands of lines).
  late List<String> lines;
  late int longest;

  /// Highlighted lines, once ready (null: plain).
  List<List<HlSeg>>? _hl;
  String? _hlFor;

  @override
  void initState() {
    super.initState();
    _split();
  }

  @override
  void didUpdateWidget(CodeLines old) {
    super.didUpdateWidget(old);
    if (old.content != widget.content) {
      _split();
      _hl = null;
      _hlFor = null;
    }
  }

  /// Highlights once per content; big files on a background isolate so the
  /// file shows (plain) at once and colors in a moment later.
  Future<void> _highlight() async {
    final content = widget.content;
    final language = widget.path == null ? null : languageForPath(widget.path!);
    if (_hlFor == content || language == null) return;
    _hlFor = content;
    final hl = lines.length > 2000
        ? await Isolate.run(() => highlightLines(content, language))
        : highlightLines(content, language);
    if (mounted && _hlFor == content) setState(() => _hl = hl);
  }

  void _split() {
    lines = widget.content.replaceAll('\t', '    ').split('\n');
    if (lines.isNotEmpty && lines.last.isEmpty) lines.removeLast();
    longest = lines.fold<int>(0, (m, l) => math.max(m, l.length));
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(diffSettingsProvider);
    final mono = settings.codeStyle(context);
    if (settings.syntax && _hlFor != widget.content) {
      // Not during build: it calls setState when done.
      WidgetsBinding.instance.addPostFrameCallback((_) => _highlight());
    }
    final hl = settings.syntax ? _hl : null;
    final theme = syntaxTheme(context);
    Text code(int i, {bool wrap = true}) => hl == null || i >= hl.length
        ? Text(lines[i], style: mono, softWrap: wrap)
        : Text.rich(codeSpan(lineRuns(hl[i], const []), mono, theme), softWrap: wrap);
    final gutterStyle = mono.copyWith(color: DiffColors.of(context).gutter);
    final tp = TextPainter(
      text: TextSpan(text: 'MMMMMMMMMM', style: mono),
      textDirection: TextDirection.ltr,
      // Same scaling as the Text widgets it sizes (system text size setting).
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final charW = tp.width / 10;
    tp.dispose();
    final gutterW = math.max(3, lines.length.toString().length) * charW + 16;

    Widget line(int i) => Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: gutterW,
          child: Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text('${i + 1}', textAlign: TextAlign.right, style: gutterStyle),
          ),
        ),
        if (settings.wrap) Expanded(child: code(i)) else code(i, wrap: false),
      ],
    );

    return LayoutBuilder(
      builder: (context, c) {
        final list = ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: lines.length,
          itemBuilder: (context, i) => line(i),
        );
        if (settings.wrap) return SelectionArea(child: list);
        final width = math.max(c.maxWidth, gutterW + longest * charW + 24);
        return SelectionArea(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(width: width, child: list),
          ),
        );
      },
    );
  }
}

import 'dart:isolate';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/routing/routes.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/async_view.dart';
import '../../data/github/github_exception.dart';
import '../../data/github/models/models.dart';
import '../auth/auth_controller.dart';
import '../diff/diff_settings.dart';
import '../diff/syntax.dart';
import '../diff/syntax_style.dart';
import 'files_providers.dart';

const _imageExts = {'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp'};

class FileViewScreen extends StatelessWidget {
  const FileViewScreen({super.key, required this.repo, required this.path, required this.gitRef, this.blame = false});

  final RepoRef repo;
  final String path;
  final String gitRef;

  /// Open with the blame gutter on.
  final bool blame;

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
    body: FileView(repo: repo, path: path, gitRef: gitRef, showToolbar: true, initialBlame: blame),
  );
}

/// File contents with line numbers plus quick actions (history, blame, copy).
class FileView extends ConsumerStatefulWidget {
  const FileView({
    super.key,
    required this.repo,
    required this.path,
    required this.gitRef,
    this.showToolbar = true,
    this.initialBlame = false,
  });

  final RepoRef repo;
  final String path;
  final String gitRef;
  final bool showToolbar;
  final bool initialBlame;

  @override
  ConsumerState<FileView> createState() => _FileViewState();
}

class _FileViewState extends ConsumerState<FileView> {
  late bool _blame = widget.initialBlame;

  RepoRef get repo => widget.repo;
  String get path => widget.path;
  String get gitRef => widget.gitRef;

  bool get _isImage => _imageExts.contains(path.split('.').last.toLowerCase());

  /// Above the code while blame is on: progress, why it isn't shown, or nothing.
  Widget? _blameBanner(AsyncValue<List<BlameRange>>? blame, FileKey key) {
    final theme = Theme.of(context);
    Widget row(IconData icon, String text, {Widget? action}) => Material(
      color: theme.colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
        child: Row(
          children: [
            Icon(icon, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text(text, style: theme.textTheme.bodySmall)),
            ?action,
          ],
        ),
      ),
    );
    if (!ref.watch(isSignedInProvider)) {
      return row(
        Icons.lock_outline,
        "Blame comes from GitHub's GraphQL API, which needs a token.",
        action: TextButton(onPressed: () => context.push(Routes.setup), child: const Text('Sign in')),
      );
    }
    return switch (blame) {
      null || AsyncData() => null,
      AsyncError(:final error) => row(
        Icons.error_outline,
        "Couldn't load blame: ${error is GitHubException ? error.message : error}",
        action: TextButton(onPressed: () => ref.invalidate(blameProvider(key)), child: const Text('Retry')),
      ),
      _ => const LinearProgressIndicator(minHeight: 2),
    };
  }

  @override
  Widget build(BuildContext context) {
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
          if (!_isImage)
            IconButton(
              tooltip: 'Blame',
              isSelected: _blame,
              icon: const Icon(Icons.person_search_outlined, size: 18),
              onPressed: () => setState(() => _blame = !_blame),
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
      final blame = _blame && ref.watch(isSignedInProvider) ? ref.watch(blameProvider(key)) : null;
      final banner = _blame ? _blameBanner(blame, key) : null;
      body = AsyncView(
        value: ref.watch(fileContentProvider(key)),
        onRetry: () => ref.invalidate(fileContentProvider(key)),
        data: (content) => content.contains('\u0000')
            ? const EmptyView(icon: Icons.memory, message: 'Binary file not shown.')
            : Column(
                children: [
                  ?banner,
                  Expanded(
                    child: CodeLines(
                      content: content,
                      path: path,
                      blame: blame?.value,
                      onBlameTap: (r) => context.push(Routes.commit(repo, r.sha, file: path)),
                    ),
                  ),
                ],
              ),
      );
    }

    return Column(
      children: [
        if (widget.showToolbar) ...[toolbar, const Divider(height: 1)],
        Expanded(child: body),
      ],
    );
  }
}

/// Lazily-rendered source code with a line-number gutter.
class CodeLines extends ConsumerStatefulWidget {
  const CodeLines({super.key, required this.content, this.path, this.blame, this.onBlameTap});

  final String content;

  /// Blame ranges; shows the blame gutter when non-null.
  final List<BlameRange>? blame;
  final ValueChanged<BlameRange>? onBlameTap;

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
    final blame = widget.blame;
    final byLine = blame == null ? null : blameByLine(blame, lines.length);
    final blameW = byLine == null ? 0.0 : 15 * charW + 12;

    Widget line(int i) => Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (byLine != null)
          _BlameCell(
            range: byLine[i],
            first: i == 0 || byLine[i - 1] != byLine[i],
            width: blameW,
            style: gutterStyle,
            onTap: widget.onBlameTap,
          ),
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
        final width = math.max(c.maxWidth, blameW + gutterW + longest * charW + 24);
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

/// One line's blame: who and when at the start of each range, and a bar
/// whose color fades with the change's age (GitHub's 1-10 buckets).
class _BlameCell extends StatelessWidget {
  const _BlameCell({required this.range, required this.first, required this.width, required this.style, this.onTap});

  final BlameRange? range;
  final bool first;
  final double width;
  final TextStyle style;
  final ValueChanged<BlameRange>? onTap;

  /// `5m`, `3h`, `2d`, `4mo`, `2y`.
  static String age(DateTime date, {DateTime? now}) {
    final d = (now ?? DateTime.now()).difference(date);
    if (d.inHours < 1) return '${d.inMinutes}m';
    if (d.inDays < 1) return '${d.inHours}h';
    if (d.inDays < 31) return '${d.inDays}d';
    if (d.inDays < 365) return '${d.inDays ~/ 30}mo';
    return '${d.inDays ~/ 365}y';
  }

  @override
  Widget build(BuildContext context) {
    final r = range;
    final scheme = Theme.of(context).colorScheme;
    final heat = r == null ? Colors.transparent : Color.lerp(scheme.primary, scheme.outlineVariant, (r.age - 1) / 9)!;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: r == null || onTap == null ? null : () => onTap!(r),
      child: Container(
        width: width,
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(color: heat, width: 3),
            top: first && r != null ? BorderSide(color: scheme.outlineVariant, width: 0.5) : BorderSide.none,
          ),
        ),
        padding: const EdgeInsets.only(left: 6, right: 4),
        child: first && r != null
            ? Text(
                '${age(r.date)} ${r.authorLogin ?? r.authorName}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: style.copyWith(color: scheme.onSurfaceVariant),
              )
            : Text('', style: style),
      ),
    );
  }
}

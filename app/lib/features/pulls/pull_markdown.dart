import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/markdown/github_refs.dart';
import '../../core/markdown/markdown.dart';
import '../../core/markdown/markdown_view.dart';
import '../../core/routing/routes.dart';
import '../../core/theme/app_theme.dart';
import '../../data/github/models/models.dart';
import '../diff/syntax.dart';
import '../diff/syntax_style.dart';

/// A pull request description or review comment as GitHub shows it: Markdown,
/// `#123` / `@user` / SHA links, fenced code highlighted in the user's code
/// font. Links to pull requests, commits and repos open in the app; anything
/// else opens in the browser.
class PullMarkdown extends StatelessWidget {
  const PullMarkdown(this.text, {super.key, required this.repo, this.selectable = true});

  final String text;
  final RepoRef repo;
  final bool selectable;

  @override
  Widget build(BuildContext context) => MarkdownView(
    linkGitHubRefs(parseMarkdown(text), owner: repo.owner, repo: repo.name),
    selectable: selectable,
    codeStyle: AppTheme.mono(context, size: 13),
    onLink: (url) => openGitHubLink(context, repo, url),
    highlight: (code, info, base) {
      final language = languageForFence(info);
      if (language == null) return null;
      final theme = syntaxTheme(context);
      final lines = highlightLines(code, language);
      return TextSpan(
        style: base,
        children: [
          for (final (i, line) in lines.indexed) ...[
            if (i > 0) const TextSpan(text: '\n'),
            codeSpan(lineRuns(line, const []), base, theme),
          ],
        ],
      );
    },
  );
}

/// Opens [url] from Markdown in [repo]: in the app when it has a screen for
/// it, else in the browser. Relative links point into the repo on github.com.
Future<void> openGitHubLink(BuildContext context, RepoRef repo, String url) async {
  final absolute = Uri.tryParse(url)?.hasScheme ?? false
      ? url
      : 'https://github.com/${repo.owner}/${repo.name}/blob/HEAD/${url.replaceFirst(RegExp(r'^\./|^/'), '')}';
  if (Routes.fromGitHubUrl(absolute) case final route?) {
    await context.push(route);
    return;
  }
  final uri = Uri.tryParse(absolute);
  if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
}

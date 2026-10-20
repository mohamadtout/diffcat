import 'package:flutter/material.dart';

import '../../data/github/models/models.dart';
import '../theme/app_theme.dart';

class UserAvatar extends StatelessWidget {
  const UserAvatar({super.key, this.url, required this.fallback, this.size = 32});

  final String? url;
  final String fallback;
  final double size;

  @override
  Widget build(BuildContext context) => CircleAvatar(
    radius: size / 2,
    // Quieter than the default primary container: a column of initials shouldn't outweigh the titles.
    backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
    foregroundColor: Theme.of(context).colorScheme.onSecondaryContainer,
    foregroundImage: url == null ? null : NetworkImage(url!),
    child: Text(fallback.isEmpty ? '?' : fallback[0].toUpperCase(), style: TextStyle(fontSize: size * 0.4)),
  );
}

/// Single-letter git status badge (A/M/D/R…).
class StatusBadge extends StatelessWidget {
  const StatusBadge(this.status, {super.key});

  final FileChangeStatus status;

  @override
  Widget build(BuildContext context) {
    final c = DiffColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    final color = switch (status) {
      FileChangeStatus.added => c.addFg,
      FileChangeStatus.removed => c.delFg,
      FileChangeStatus.renamed || FileChangeStatus.copied => c.hunkFg,
      _ => scheme.tertiary,
    };
    return Container(
      width: 20,
      height: 20,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4)),
      child: Text(
        status.letter,
        style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 11, fontFamily: AppTheme.monoFamily),
      ),
    );
  }
}

/// "+12 −3" counter.
class LineCounts extends StatelessWidget {
  const LineCounts({super.key, required this.additions, required this.deletions});

  final int additions;
  final int deletions;

  @override
  Widget build(BuildContext context) {
    final c = DiffColors.of(context);
    final style = TextStyle(fontFamily: AppTheme.monoFamily, fontSize: 12);
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '+$additions',
            style: style.copyWith(color: c.addFg),
          ),
          const TextSpan(text: ' '),
          TextSpan(
            text: '−$deletions',
            style: style.copyWith(color: c.delFg),
          ),
        ],
      ),
    );
  }
}

/// Monospace short sha chip.
class ShaChip extends StatelessWidget {
  const ShaChip(this.sha, {super.key});

  final String sha;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(
      sha.length > 7 ? sha.substring(0, 7) : sha,
      style: TextStyle(fontFamily: AppTheme.monoFamily, fontSize: 12),
    ),
  );
}

/// The heading of a group of settings or list entries, in the primary color.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.padding = const EdgeInsets.fromLTRB(16, 20, 16, 8)});

  final String title;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: padding,
      child: Text(title, style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary)),
    );
  }
}

/// Selectable text shown to [maxLines] lines, with "More" / "Less" when it's
/// longer: commit bodies shouldn't push the diff off the first screen.
class ExpandableText extends StatefulWidget {
  const ExpandableText(this.text, {super.key, this.maxLines = 2, this.style});

  final String text;
  final int maxLines;
  final TextStyle? style;

  @override
  State<ExpandableText> createState() => _ExpandableTextState();
}

class _ExpandableTextState extends State<ExpandableText> {
  var _open = false;

  @override
  Widget build(BuildContext context) {
    final style = widget.style ?? Theme.of(context).textTheme.bodyMedium;
    return LayoutBuilder(
      builder: (context, c) {
        final painter = TextPainter(
          text: TextSpan(text: widget.text, style: style),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
          maxLines: widget.maxLines,
        )..layout(maxWidth: c.maxWidth);
        final long = painter.didExceedMaxLines;
        painter.dispose();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Collapsed: plain text with an ellipsis (SelectableText would scroll inside its lines).
            if (_open || !long)
              SelectableText(widget.text, style: style)
            else
              Text(widget.text, style: style, maxLines: widget.maxLines, overflow: TextOverflow.ellipsis),
            if (long)
              TextButton(
                style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
                onPressed: () => setState(() => _open = !_open),
                child: Text(_open ? 'Less' : 'More'),
              ),
          ],
        );
      },
    );
  }
}

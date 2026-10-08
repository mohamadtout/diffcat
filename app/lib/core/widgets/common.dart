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

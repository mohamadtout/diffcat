import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/github/github_exception.dart';
import '../routing/routes.dart';
import 'mascot.dart';

/// Standard loading / error / data rendering for an [AsyncValue].
class AsyncView<T> extends StatelessWidget {
  const AsyncView({super.key, required this.value, required this.data, this.onRetry, this.error});

  final AsyncValue<T> value;
  final Widget Function(T data) data;
  final VoidCallback? onRetry;

  /// Custom error UI; defaults to [ErrorView].
  final Widget Function(Object error)? error;

  @override
  Widget build(BuildContext context) => switch (value) {
    AsyncData(:final value) => data(value),
    AsyncError(error: final e) => error?.call(e) ?? ErrorView(error: e, onRetry: onRetry),
    _ => const Center(child: CircularProgressIndicator()),
  };
}

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.error, this.onRetry});

  final Object error;
  final VoidCallback? onRetry;

  static String _clock(DateTime at) => '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';

  String get _message {
    final e = error;
    if (e is GitHubException) {
      if (e.isUnauthorized) {
        return 'GitHub rejected the token. Update it in Settings.';
      }
      if (e.isNotFound) {
        return 'Not found — the ref may not exist or the token lacks access.';
      }
      return e.toString();
    }
    return e.toString();
  }

  @override
  Widget build(BuildContext context) {
    final e = error;
    if (e is GitHubException && e.isRateLimited) return _rateLimited(context, e);
    return EmptyView(
      icon: Icons.error_outline,
      iconColor: Theme.of(context).colorScheme.error,
      message: _message,
      action: onRetry == null ? null : FilledButton.tonal(onPressed: onRetry, child: const Text('Retry')),
    );
  }

  /// Retrying can't help until the reset, so say when that is, and offer the
  /// real way out when there is one: signing in raises the limit 60 → 5,000.
  Widget _rateLimited(BuildContext context, GitHubException e) {
    final at = e.rateLimitResetAt!.toLocal();
    final minutes = at.difference(DateTime.now()).inMinutes;
    final when = minutes < 1 ? 'in under a minute' : 'in $minutes min';
    final retry = onRetry == null ? null : TextButton(onPressed: onRetry, child: const Text('Retry'));
    return EmptyView(
      icon: Icons.hourglass_bottom,
      title: "GitHub's hourly limit is used up",
      message: e.signedOut
          ? 'Without signing in GitHub allows 60 requests an hour. It resets at ${_clock(at)} ($when).'
          : 'It resets at ${_clock(at)} ($when). Downloaded repos still open offline.',
      action: e.signedOut
          ? Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(
                  onPressed: () => context.push(Routes.setup),
                  child: const Text('Sign in for 5,000 an hour'),
                ),
                ?retry,
              ],
            )
          : retry,
    );
  }
}

/// Nothing to show: an icon (or the mascot), an optional title, the message
/// and, when there is one, the obvious next step as [action]. It sits in the
/// upper part of the space rather than dead centre, and scrolls instead of
/// overflowing when space is short.
class EmptyView extends StatelessWidget {
  const EmptyView({
    super.key,
    required this.icon,
    required this.message,
    this.title,
    this.action,
    this.iconColor,
    this.mascot = false,
  });

  final IconData icon;
  final String message;
  final String? title;

  /// Usually a [FilledButton.tonal]; a [Wrap] for two.
  final Widget? action;
  final Color? iconColor;

  /// The Diffcat cat in place of [icon], for calm "all clear" or "nothing yet"
  /// moments. Never on working screens or errors. Hidden when space is short.
  final bool mascot;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget content({required bool roomy}) => ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 480),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (mascot && roomy)
              const Mascot()
            else
              Icon(icon, size: 40, color: iconColor ?? theme.colorScheme.outline),
            const SizedBox(height: 12),
            if (title != null) ...[
              Text(title!, textAlign: TextAlign.center, style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
            ],
            Text(
              message,
              textAlign: TextAlign.center,
              style: title == null
                  ? null
                  : theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
    return LayoutBuilder(
      builder: (context, c) {
        // Inside a list (e.g. under a RefreshIndicator): just the content.
        if (!c.hasBoundedHeight) return Center(child: content(roomy: true));
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: c.maxHeight, minWidth: c.maxWidth),
            child: Align(
              alignment: const Alignment(0, -0.4),
              child: content(roomy: c.maxHeight >= 360),
            ),
          ),
        );
      },
    );
  }
}

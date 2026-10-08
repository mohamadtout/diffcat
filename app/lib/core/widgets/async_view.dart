import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/github/github_exception.dart';

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

  String get _message {
    final e = error;
    if (e is GitHubException) {
      if (e.isRateLimited) {
        final at = e.rateLimitResetAt!;
        return 'GitHub rate limit reached. Resets at '
            '${TimeOfDay.fromDateTime(at.toLocal()).hour.toString().padLeft(2, '0')}:'
            '${at.toLocal().minute.toString().padLeft(2, '0')}.';
      }
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
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, size: 40, color: Theme.of(context).colorScheme.error),
          const SizedBox(height: 12),
          Text(_message, textAlign: TextAlign.center),
          if (onRetry != null) ...[
            const SizedBox(height: 12),
            FilledButton.tonal(onPressed: onRetry, child: const Text('Retry')),
          ],
        ],
      ),
    ),
  );
}

class EmptyView extends StatelessWidget {
  const EmptyView({super.key, required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 40, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
        ],
      ),
    ),
  );
}

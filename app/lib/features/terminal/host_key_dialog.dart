import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// `SHA256:Zm9vYmFy…` as `SHA256:` plus 4-character groups, so two keys can be
/// compared group by group instead of as one string wrapping mid-way.
String groupFingerprint(String fingerprint) {
  final colon = fingerprint.indexOf(':');
  final prefix = colon < 0 ? '' : fingerprint.substring(0, colon + 1);
  final body = fingerprint.substring(colon + 1);
  final groups = [for (var i = 0; i < body.length; i += 4) body.substring(i, min(i + 4, body.length))];
  return '$prefix ${groups.join(' ')}'.trim();
}

/// Asks whether to trust [hostName]'s key. [previous] is non-null when the key
/// changed since it was trusted (possible man-in-the-middle): then Cancel is
/// the emphasized, safe choice and trusting is the quiet one.
Future<bool> confirmHostKey(
  BuildContext context, {
  required String hostName,
  required String type,
  required String fingerprint,
  String? previous,
}) async {
  if (!context.mounted) return false;
  final changed = previous != null;
  final ok = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      final theme = Theme.of(ctx);
      final scheme = theme.colorScheme;
      final mono = AppTheme.mono(ctx, size: 13).copyWith(height: 1.5);
      Widget key(String label, String fp) => Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: theme.textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant)),
            SelectableText(groupFingerprint(fp), style: mono),
          ],
        ),
      );
      return AlertDialog(
        icon: Icon(changed ? Icons.gpp_bad : Icons.fingerprint, size: 32, color: changed ? scheme.error : null),
        title: Text(changed ? 'Host key changed' : 'Trust this host?'),
        scrollable: true,
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              changed
                  ? 'The key for $hostName differs from the one you trusted before. This could be a '
                        'man-in-the-middle attack. Only continue if you know the host was reinstalled or its key '
                        'was changed.'
                  : 'First connection to $hostName. Compare the fingerprint with the one on the host:',
            ),
            if (previous != null) key('Trusted before', previous),
            key(changed ? 'Now ($type)' : type, fingerprint),
            if (!changed) ...[
              const SizedBox(height: 12),
              SelectableText('ssh-keygen -lf /etc/ssh/ssh_host_*_key.pub', style: mono.copyWith(fontSize: 12)),
            ],
          ],
        ),
        actions: changed
            ? [
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: scheme.error),
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Trust new key'),
                ),
                FilledButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              ]
            : [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Trust')),
              ],
      );
    },
  );
  return ok ?? false;
}

import 'package:flutter/material.dart';

/// Asks whether to trust [hostName]'s key. [previous] is non-null when the key
/// changed since it was trusted (possible man-in-the-middle).
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
    builder: (ctx) => AlertDialog(
      icon: Icon(changed ? Icons.gpp_bad : Icons.fingerprint, color: changed ? Theme.of(ctx).colorScheme.error : null),
      title: Text(changed ? 'HOST KEY CHANGED' : 'Trust this host?'),
      content: SelectableText(
        changed
            ? 'The key for $hostName differs from the one you trusted before. '
                  'This could be a man-in-the-middle attack.\n\nOld: $previous\nNew: $fingerprint ($type)'
            : 'First connection to $hostName.\n\n$type\n$fingerprint\n\n'
                  'Compare with `ssh-keygen -lf /etc/ssh/ssh_host_*_key.pub` on the host.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(
          style: changed ? FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error) : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(changed ? 'Trust new key' : 'Trust'),
        ),
      ],
    ),
  );
  return ok ?? false;
}

import 'package:flutter/material.dart';

/// The Diffcat cat (glasses with a − and a + lens), drawn in one theme color.
/// Decorative: for first run and a few calm empty states only.
class Mascot extends StatelessWidget {
  const Mascot({super.key, this.size = 88});

  final double size;

  @override
  Widget build(BuildContext context) => Image.asset(
    'assets/mascot/cat.png',
    width: size,
    height: size * 265 / 288,
    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.45),
    colorBlendMode: BlendMode.srcIn,
    excludeFromSemantics: true,
    filterQuality: FilterQuality.medium,
  );
}

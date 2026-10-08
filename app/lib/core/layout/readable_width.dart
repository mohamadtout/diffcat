import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Keeps list-style screens (repo list, settings, downloads…) at a readable
/// width on tablets and desktops instead of stretching rows edge to edge.
///
/// It hands [builder] side padding rather than shrinking the list, so the
/// list still scrolls when dragged anywhere on screen, margins included.
class ReadableWidth extends StatelessWidget {
  const ReadableWidth({super.key, required this.builder, this.maxWidth = 720});

  final Widget Function(EdgeInsets sides) builder;
  final double maxWidth;

  /// Side padding that centers [maxWidth] of content in [available].
  static EdgeInsets sidesFor(double available, {double maxWidth = 720}) =>
      EdgeInsets.symmetric(horizontal: math.max(0, (available - maxWidth) / 2));

  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, c) => builder(sidesFor(c.maxWidth, maxWidth: maxWidth)));
}

import 'package:flutter/widgets.dart';

/// Material 3 window size classes. Phones are compact; foldables and small
/// tablets are medium; iPads / large tablets in landscape are expanded.
enum WindowSize {
  compact,
  medium,
  expanded;

  static WindowSize of(BuildContext context) => fromWidth(MediaQuery.sizeOf(context).width);

  static WindowSize fromWidth(double w) => w < 600
      ? compact
      : w < 840
      ? medium
      : expanded;

  /// Wide enough to show list + detail side by side.
  bool get isSplit => this == expanded;
}

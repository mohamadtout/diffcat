import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/storage.dart';
import 'breakpoints.dart';

/// Whether wide layouts hide the list to give the detail the full width.
/// Shared by every [SplitView] and remembered across launches.
final splitCollapsedProvider = NotifierProvider<SplitCollapsed, bool>(SplitCollapsed.new);

class SplitCollapsed extends Notifier<bool> {
  @override
  bool build() => ref.watch(sharedPrefsProvider).getBool(StoreKeys.splitCollapsed) ?? false;

  void toggle() {
    state = !state;
    ref.read(sharedPrefsProvider).setBool(StoreKeys.splitCollapsed, state);
  }
}

/// List/detail layout. On wide windows (tablets, iPad, foldables open) the
/// detail renders beside the list; on phones only [master] is shown and the
/// caller should push the detail as a route instead.
///
/// On wide windows a thin handle between the panes collapses the list so the
/// detail (e.g. a diff) gets the full width. The list stays mounted while
/// hidden, so its scroll position survives.
class SplitView extends ConsumerWidget {
  const SplitView({
    super.key,
    required this.master,
    required this.detail,
    this.placeholder = 'Select an item',
    this.masterWidth = 380,
  });

  final Widget master;
  final Widget? detail;
  final String placeholder;
  final double masterWidth;

  /// Whether callers should show details inline instead of pushing routes.
  static bool isActive(BuildContext context) => WindowSize.of(context).isSplit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!isActive(context)) return master;
    // Nothing to give the space to until something is selected.
    final collapsed = ref.watch(splitCollapsedProvider) && detail != null;
    return Row(
      children: [
        TweenAnimationBuilder<double>(
          tween: Tween(end: collapsed ? 0 : masterWidth),
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          builder: (context, width, child) => SizedBox(
            width: width,
            child: Visibility(
              visible: width > 0,
              maintainState: true,
              child: ClipRect(
                child: OverflowBox(
                  alignment: Alignment.centerLeft,
                  minWidth: masterWidth,
                  maxWidth: masterWidth,
                  child: child,
                ),
              ),
            ),
          ),
          child: master,
        ),
        _CollapseHandle(
          collapsed: collapsed,
          onToggle: detail == null ? null : () => ref.read(splitCollapsedProvider.notifier).toggle(),
        ),
        Expanded(
          child:
              detail ??
              Center(
                child: Text(placeholder, style: TextStyle(color: Theme.of(context).colorScheme.outline)),
              ),
        ),
      ],
    );
  }
}

/// The divider between the panes, doubling as the collapse/expand control.
class _CollapseHandle extends StatelessWidget {
  const _CollapseHandle({required this.collapsed, required this.onToggle});

  final bool collapsed;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: collapsed ? 'Show list' : 'Hide list (full-width view)',
      child: Material(
        color: scheme.surfaceContainerLow,
        child: InkWell(
          onTap: onToggle,
          child: SizedBox(
            width: 20,
            child: Column(
              children: [
                const SizedBox(height: 8),
                Icon(
                  collapsed ? Icons.chevron_right : Icons.chevron_left,
                  size: 18,
                  color: onToggle == null ? scheme.outlineVariant : scheme.onSurfaceVariant,
                ),
                Expanded(child: VerticalDivider(width: 1, color: scheme.outlineVariant)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

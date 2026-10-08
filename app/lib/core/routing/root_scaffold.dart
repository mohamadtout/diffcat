import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../layout/breakpoints.dart';

/// Top-level navigation: bottom bar on phones (top-level screens only, so it
/// never stacks with the repo tab bar), navigation rail on tablets / iPad.
class RootScaffold extends StatelessWidget {
  const RootScaffold({super.key, required this.shell});

  final StatefulNavigationShell shell;

  static const _destinations = [
    (Icons.inventory_2_outlined, Icons.inventory_2, 'Repos'),
    (Icons.terminal_outlined, Icons.terminal, 'Terminal'),
    (Icons.settings_outlined, Icons.settings, 'Settings'),
  ];

  void _go(int i) => shell.goBranch(i, initialLocation: i == shell.currentIndex);

  @override
  Widget build(BuildContext context) {
    final size = WindowSize.of(context);
    if (size == WindowSize.compact) {
      final delegate = GoRouter.of(context).routerDelegate;
      return ListenableBuilder(
        listenable: delegate,
        builder: (context, _) {
          // `state` is the top route, including pushed ones (currentConfiguration.uri
          // keeps the base location when a route is pushed).
          final segments = delegate.state.uri.pathSegments.where((s) => s.isNotEmpty);
          final atRoot = segments.length <= 1;
          return Scaffold(
            body: shell,
            bottomNavigationBar: atRoot
                ? NavigationBar(
                    selectedIndex: shell.currentIndex,
                    onDestinationSelected: _go,
                    destinations: [
                      for (final (icon, selected, label) in _destinations)
                        NavigationDestination(icon: Icon(icon), selectedIcon: Icon(selected), label: label),
                    ],
                  )
                : null,
          );
        },
      );
    }
    return Scaffold(
      body: Row(
        children: [
          SafeArea(
            right: false,
            child: NavigationRail(
              selectedIndex: shell.currentIndex,
              onDestinationSelected: _go,
              labelType: NavigationRailLabelType.all,
              destinations: [
                for (final (icon, selected, label) in _destinations)
                  NavigationRailDestination(icon: Icon(icon), selectedIcon: Icon(selected), label: Text(label)),
              ],
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(child: shell),
        ],
      ),
    );
  }
}

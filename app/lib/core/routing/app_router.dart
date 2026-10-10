import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/github/models/repo.dart';
import '../../features/auth/auth_controller.dart';
import '../../features/auth/token_screen.dart';
import '../../features/commands/commands_screen.dart';
import '../../features/commits/commit_screen.dart';
import '../../features/compare/changed_since_screen.dart';
import '../../features/compare/compare_screen.dart';
import '../../features/diff/code_view_settings_screen.dart';
import '../../features/files/file_history_screen.dart';
import '../../features/files/file_view_screen.dart';
import '../../features/inbox/inbox_screen.dart';
import '../../features/notifications/local_notifications.dart';
import '../../features/offline/downloads_screen.dart';
import '../../features/pulls/pull_screen.dart';
import '../../features/repo/repo_screen.dart';
import '../../features/repos/repo_list_settings_screen.dart';
import '../../features/repos/repos_screen.dart';
import '../../features/settings/settings_screen.dart';
import '../../features/terminal/host_edit_screen.dart';
import '../../features/terminal/hosts_screen.dart';
import '../../features/terminal/terminal_appearance_screen.dart';
import '../../features/terminal/terminal_screen.dart';
import 'root_scaffold.dart';
import 'routes.dart';

final routerProvider = Provider<GoRouter>((ref) {
  // Re-run redirects whenever auth state changes.
  final authChanges = ValueNotifier<int>(0);
  ref.listen(authTokenProvider, (_, _) => authChanges.value++);
  ref.onDispose(authChanges.dispose);

  final router = GoRouter(
    initialLocation: Routes.splash,
    refreshListenable: authChanges,
    redirect: (context, state) {
      final auth = ref.read(authTokenProvider);
      final loc = state.matchedLocation;
      if (!auth.hasValue && !auth.hasError) return loc == Routes.splash ? null : Routes.splash;
      // Cold start from a notification tap lands on its target.
      if (loc == Routes.splash) return ref.read(localNotificationsProvider).takeLaunchRoute() ?? Routes.repos;
      // Sign-in is optional; leave the sign-in screen once it succeeded.
      if (loc == Routes.setup && auth.value != null) return Routes.repos;
      return null;
    },
    routes: [
      GoRoute(path: Routes.splash, builder: (_, _) => const _Splash()),
      GoRoute(path: Routes.setup, builder: (_, _) => const TokenScreen()),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => RootScaffold(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.repos,
                builder: (_, _) => const ReposScreen(),
                routes: [
                  GoRoute(
                    path: ':owner/:name',
                    builder: (_, s) => RepoScreen(
                      key: ValueKey(s.uri.toString()),
                      repo: _repo(s),
                      initialTab: s.uri.queryParameters['tab'],
                      initialRef: s.uri.queryParameters['ref'],
                    ),
                    routes: [
                      GoRoute(
                        path: 'commit/:sha',
                        builder: (_, s) => CommitScreen(
                          repo: _repo(s),
                          sha: s.pathParameters['sha']!,
                          focusPath: s.uri.queryParameters['file'],
                        ),
                      ),
                      GoRoute(
                        path: 'compare',
                        builder: (_, s) => CompareScreen(
                          repo: _repo(s),
                          base: s.uri.queryParameters['base']!,
                          head: s.uri.queryParameters['head']!,
                          focusPath: s.uri.queryParameters['file'],
                        ),
                      ),
                      GoRoute(
                        path: 'pull/:number',
                        builder: (_, s) => PullScreen(repo: _repo(s), number: int.parse(s.pathParameters['number']!)),
                      ),
                      GoRoute(
                        path: 'file',
                        builder: (_, s) => FileViewScreen(
                          repo: _repo(s),
                          path: s.uri.queryParameters['path']!,
                          gitRef: s.uri.queryParameters['ref']!,
                          blame: s.uri.queryParameters['blame'] == '1',
                        ),
                      ),
                      GoRoute(
                        path: 'history',
                        builder: (_, s) => FileHistoryScreen(
                          repo: _repo(s),
                          path: s.uri.queryParameters['path']!,
                          gitRef: s.uri.queryParameters['ref']!,
                        ),
                      ),
                      GoRoute(
                        path: 'since',
                        builder: (_, s) => ChangedSinceScreen(
                          repo: _repo(s),
                          initialHead: s.uri.queryParameters['ref'],
                          initialBase: s.uri.queryParameters['base'],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: Routes.inbox, builder: (_, _) => const InboxScreen())],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.terminal,
                builder: (_, _) => const HostsScreen(),
                routes: [
                  GoRoute(
                    path: 'edit',
                    builder: (_, s) => HostEditScreen(hostId: s.uri.queryParameters['id']),
                  ),
                  GoRoute(
                    path: ':hostId',
                    builder: (_, s) => TerminalScreen(hostId: s.pathParameters['hostId']!),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.settings,
                builder: (_, _) => const SettingsScreen(),
                routes: [
                  GoRoute(path: 'commands', builder: (_, _) => const CommandsScreen()),
                  GoRoute(path: 'terminal', builder: (_, _) => const TerminalAppearanceScreen()),
                  GoRoute(path: 'code', builder: (_, _) => const CodeViewSettingsScreen()),
                  GoRoute(
                    path: 'repos',
                    builder: (_, _) => const RepoListSettingsScreen(),
                    routes: [GoRoute(path: 'folders', builder: (_, _) => const RepoFoldersScreen())],
                  ),
                  GoRoute(
                    path: 'downloads',
                    builder: (_, _) => const DownloadsScreen(),
                    routes: [
                      GoRoute(
                        path: ':owner/:name',
                        builder: (_, s) => SavedRepoScreen(repo: _repo(s)),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});

RepoRef _repo(GoRouterState s) => (owner: s.pathParameters['owner']!, name: s.pathParameters['name']!);

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) => const Scaffold(body: Center(child: CircularProgressIndicator()));
}

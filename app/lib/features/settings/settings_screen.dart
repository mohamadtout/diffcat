import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/layout/readable_width.dart';
import '../../core/routing/routes.dart';
import '../../core/storage/storage.dart';
import '../../core/utils/relative_time.dart';
import '../../core/widgets/common.dart';
import '../auth/auth_controller.dart';
import '../notifications/background.dart';
import '../notifications/local_notifications.dart';
import '../notifications/watch_controller.dart';
import '../offline/offline_providers.dart';
import '../offline/offline_store.dart';

final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);

class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() =>
      ThemeMode.values.asNameMap()[ref.watch(sharedPrefsProvider).getString(StoreKeys.themeMode)] ?? ThemeMode.system;

  void set(ThemeMode m) {
    state = m;
    ref.read(sharedPrefsProvider).setString(StoreKeys.themeMode, m.name);
  }
}

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final viewer = ref.watch(viewerProvider).value;
    final watched = ref.watch(watchedReposProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ReadableWidth(
        builder: (sides) => ListView(
          padding: sides,
          children: [
            const SectionHeader('GitHub account'),
            if (ref.watch(isSignedInProvider))
              ListTile(
                leading: UserAvatar(url: viewer?.avatarUrl, fallback: viewer?.login ?? '?'),
                title: Text(viewer?.login ?? '…'),
                subtitle: Text(viewer?.name ?? 'Personal access token'),
                trailing: TextButton(
                  onPressed: () => ref.read(authTokenProvider.notifier).signOut(),
                  child: const Text('Sign out'),
                ),
              )
            else
              ListTile(
                leading: const Icon(Icons.person_outline),
                title: const Text('Not signed in'),
                subtitle: const Text('Public repos only, up to 60 GitHub requests an hour.'),
                trailing: FilledButton.tonal(onPressed: () => context.push(Routes.setup), child: const Text('Sign in')),
              ),
            const SectionHeader('Appearance'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SegmentedButton<ThemeMode>(
                segments: const [
                  ButtonSegment(value: ThemeMode.system, label: Text('System')),
                  ButtonSegment(value: ThemeMode.light, label: Text('Light')),
                  ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
                ],
                selected: {ref.watch(themeModeProvider)},
                onSelectionChanged: (s) => ref.read(themeModeProvider.notifier).set(s.first),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.code),
              title: const Text('Code view'),
              subtitle: const Text('Font, full files, diff colors'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push(Routes.codeView),
            ),
            ListTile(
              leading: const Icon(Icons.folder_copy_outlined),
              title: const Text('Repository list'),
              subtitle: const Text('Folders, sort, hidden repos and accounts, what to load'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push(Routes.repoList),
            ),
            ListTile(
              leading: const Icon(Icons.terminal),
              title: const Text('Terminal appearance'),
              subtitle: const Text('Colors, font, background, git status bar'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push(Routes.terminalAppearance),
            ),
            const SectionHeader('Offline'),
            const _DownloadsTile(),
            const _DataSaverTile(),
            const SectionHeader('Notifications'),
            const _NotificationsSection(),
            for (final r in watched)
              ListTile(
                dense: true,
                leading: const Icon(Icons.visibility_outlined),
                title: Text(r),
                trailing: IconButton(
                  tooltip: 'Stop watching',
                  icon: const Icon(Icons.close),
                  onPressed: () {
                    final parts = r.split('/');
                    ref.read(watchedReposProvider.notifier).unwatch((owner: parts[0], name: parts[1]));
                  },
                ),
              ),
            const SectionHeader('Tools'),
            ListTile(
              leading: const Icon(Icons.smart_button_outlined),
              title: const Text('Command buttons'),
              subtitle: const Text('Custom API console and SSH/lazygit buttons'),
              onTap: () => context.push(Routes.commands),
            ),
            ListTile(
              leading: const Icon(Icons.dns_outlined),
              title: const Text('SSH hosts'),
              onTap: () => context.go(Routes.terminal),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

class _NotificationsSection extends ConsumerWidget {
  const _NotificationsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifications = ref.watch(localNotificationsProvider);
    final watched = ref.watch(watchedReposProvider);
    final poll = ref.watch(pollControllerProvider);
    final includeOwn = ref.watch(notifyIncludeOwnProvider);
    final last = poll.last;
    final theme = Theme.of(context);

    final status = !notifications.enabled
        ? 'Notifications unavailable on this platform.'
        : watched.isEmpty
        ? 'Not watching any repo. Tap the bell on a repo to start.'
        : last == null
        ? 'Watching ${watched.length} repo(s). Not checked yet.'
        : 'Watching ${watched.length} repo(s). Last check ${relativeTime(last.at)}'
              '${last.events > 0 ? ' · ${last.events} new' : ''}'
              '${last.errors.isNotEmpty ? ' · ${last.errors.length} failed' : ''}.';

    final copy = notificationCopy(theme.platform);
    return Column(
      children: [
        ListTile(
          leading: Icon(watched.isEmpty ? Icons.notifications_none : Icons.notifications_active),
          title: Text(copy.schedule),
          subtitle: Text(status),
          trailing: poll.running
              ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : TextButton(
                  onPressed: watched.isEmpty ? null : () => ref.read(pollControllerProvider.notifier).checkNow(),
                  child: const Text('Check now'),
                ),
        ),
        if (last != null && last.errors.isNotEmpty)
          for (final e in last.errors.entries)
            ListTile(
              dense: true,
              leading: Icon(Icons.error_outline, color: theme.colorScheme.error),
              title: Text(e.key),
              subtitle: Text(e.value, maxLines: 2, overflow: TextOverflow.ellipsis),
            ),
        SwitchListTile(
          secondary: const Icon(Icons.rate_review_outlined),
          title: const Text('Pull requests that need you'),
          subtitle: Text(
            ref.watch(isSignedInProvider)
                ? 'Review requests, mentions and replies on any repo, from your GitHub notifications. '
                      'Checked about every minute while Diffcat is open'
                : 'Sign in to be notified about review requests, mentions and replies',
          ),
          value: ref.watch(notifyReviewRequestsProvider) && ref.watch(isSignedInProvider),
          onChanged: ref.watch(isSignedInProvider)
              ? (v) => ref.read(notifyReviewRequestsProvider.notifier).set(v)
              : null,
        ),
        SwitchListTile(
          secondary: const Icon(Icons.person_outline),
          title: const Text('Notify about my own activity'),
          subtitle: const Text('Your own commits and PRs (merges always notify)'),
          value: includeOwn,
          onChanged: (v) => ref.read(notifyIncludeOwnProvider.notifier).set(v),
        ),
        ListTile(
          leading: const Icon(Icons.battery_alert_outlined),
          title: const Text('Notifications late or missing?'),
          subtitle: Text(copy.help),
          trailing: TextButton(
            onPressed: () async {
              final ok = await notifications.requestPermission();
              if (context.mounted) {
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text(ok ? 'Notifications allowed' : 'Notifications blocked')));
              }
            },
            child: const Text('Permission'),
          ),
        ),
      ],
    );
  }
}

/// Platform-specific wording for the notification settings. iOS has no
/// background checks yet (docs/roadmap.md), so it must not promise them.
({String schedule, String help}) notificationCopy(TargetPlatform platform) => switch (platform) {
  TargetPlatform.iOS => (
    schedule: 'Checks GitHub in the background and when you open the app',
    help:
        'iOS decides when background checks run, usually a few times a day, so notifications can be late. '
        'Keep Background App Refresh on and notifications allowed (Settings → Diffcat).',
  ),
  _ => (
    schedule: 'Checks GitHub about every ${pollInterval.inMinutes} min',
    help:
        'Android may delay background checks to save battery. Set Diffcat\'s battery usage to '
        '"Unrestricted" (Settings → Apps → Diffcat → Battery).',
  ),
};

class _DataSaverTile extends ConsumerWidget {
  const _DataSaverTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final on = ref.watch(dataSaverProvider);
    return SwitchListTile(
      secondary: const Icon(Icons.data_saver_on_outlined),
      title: const Text('Data saver'),
      subtitle: Text(
        on
            ? 'Downloaded repos open from the device, as of their last update; only what isn\'t downloaded '
                  'uses GitHub requests. Update a download to refresh it.'
            : 'Commits, branches and pull requests load live. Downloaded diffs and files still cost no '
                  'requests, and downloads stand in when GitHub can\'t be reached.',
      ),
      value: on,
      onChanged: ref.read(dataSaverProvider.notifier).set,
    );
  }
}

class _DownloadsTile extends ConsumerWidget {
  const _DownloadsTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(offlineRevisionProvider);
    final store = ref.watch(offlineStoreProvider);
    final count = store?.repos.length ?? 0;
    return ListTile(
      leading: const Icon(Icons.download_for_offline_outlined),
      title: const Text('Downloads'),
      subtitle: Text(
        store == null
            ? 'Unavailable on this device'
            : count == 0
            ? 'Nothing saved. Use the download button on a repo to read it offline.'
            : '$count repo${count == 1 ? '' : 's'} · ${formatBytes(store.totalBytes)}',
      ),
      trailing: const Icon(Icons.chevron_right),
      enabled: store != null,
      onTap: () => context.push(Routes.downloads),
    );
  }
}

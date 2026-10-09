import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/github/etag_cache.dart';

/// ETags of the background notification check (see [FileEtagCache]).
/// Cleared on sign-in and sign-out: they can hold private repos' data.
Future<FileEtagCache> pollEtagCache() async =>
    FileEtagCache(Directory('${(await getApplicationSupportDirectory()).path}/poll_etags'));

/// Overridden in main() with the already-initialized instance.
final sharedPrefsProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('sharedPrefsProvider must be overridden'),
);

/// Secure storage as the whole app (and the background check) opens it.
///
/// iOS: readable after the first unlock since boot, so the background check
/// can read the token while the phone is locked, and `ThisDevice`, so secrets
/// never travel in backups or to a new phone. Android: the plugin's default
/// (AES-GCM, Keystore-wrapped key).
const appSecureStorage = FlutterSecureStorage(
  iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
);

final secureStoreProvider = Provider<SecureStore>((ref) => SecureStore(appSecureStorage));

/// Keys for everything persisted by the app. Keep in one place to avoid
/// collisions and make migrations greppable.
abstract final class StoreKeys {
  // Secure storage (Keychain / EncryptedSharedPreferences).
  static const githubToken = 'github_token';
  static String sshPassword(String hostId) => 'ssh.$hostId.password';
  static String sshPrivateKey(String hostId) => 'ssh.$hostId.key';
  static String sshPassphrase(String hostId) => 'ssh.$hostId.passphrase';

  // Shared preferences (non-secret).
  static const themeMode = 'theme_mode';
  static const watchedRepos = 'watched_repos';
  // Notification poller (see features/notifications/poller.dart).
  static const pollState = 'poll_state';
  static const lastPoll = 'poll_last_result';
  static const viewerLogin = 'viewer_login';
  static const notifyIncludeOwn = 'notify_include_own';
  static const notifyReviewRequests = 'notify_review_requests';
  static const reviewRequestsSeen = 'review_requests_seen';
  static const pinnedRepos = 'pinned_repos';
  static const recentRepos = 'recent_repos';
  static const offlineModeRepos = 'offline_mode_repos';
  static const customCommands = 'custom_commands';
  static const sshHosts = 'ssh_hosts';
  static const knownHosts = 'known_hosts';
  static const terminalAppearance = 'terminal_appearance';
  static const diffWrap = 'diff_wrap';
  static const diffFontSize = 'diff_wrap_font';
  static const diffFont = 'diff_font';
  static const diffFullFile = 'diff_full_file';
  static const diffSyntax = 'diff_syntax';
  static const diffColors = 'diff_colors';
  static const splitCollapsed = 'split_collapsed';

  /// A pull request review being written (see features/pulls/review.dart).
  static String reviewDraft(String repo, int number) => 'review_draft:${repo.toLowerCase()}#$number';
  static const secureStorageVersion = 'secure_storage_version';
}

class SecureStore {
  SecureStore(this._storage);
  final FlutterSecureStorage _storage;

  /// Re-saves every secret once so items written before [appSecureStorage]
  /// set its keychain accessibility get the new one (an existing item keeps
  /// the level it was written with). Harmless on Android.
  static Future<void> migrate(FlutterSecureStorage storage, SharedPreferences prefs) async {
    const version = 2;
    if ((prefs.getInt(StoreKeys.secureStorageVersion) ?? 1) >= version) return;
    try {
      final secrets = {...await storage.readAll()}; // a copy: the loop rewrites the store
      for (final e in secrets.entries) {
        await storage.delete(key: e.key);
        await storage.write(key: e.key, value: e.value);
      }
      await prefs.setInt(StoreKeys.secureStorageVersion, version);
    } on Object catch (e) {
      // Try again next launch; the secrets are still readable as they are.
      debugPrint('Secure storage migration failed: ${e.runtimeType}');
    }
  }

  Future<String?> read(String key) => _storage.read(key: key);

  Future<void> write(String key, String? value) =>
      value == null || value.isEmpty ? _storage.delete(key: key) : _storage.write(key: key, value: value);

  Future<void> delete(String key) => _storage.delete(key: key);
}

/// Helpers for JSON values in SharedPreferences.
extension JsonPrefs on SharedPreferences {
  List<Map<String, dynamic>> readJsonList(String key) {
    final raw = getString(key);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List<dynamic>).cast<Map<String, dynamic>>();
    } on FormatException {
      return [];
    }
  }

  Future<void> writeJsonList(String key, List<Map<String, dynamic>> value) => setString(key, jsonEncode(value));

  Map<String, String> readStringMap(String key) {
    final raw = getString(key);
    if (raw == null) return {};
    try {
      return (jsonDecode(raw) as Map<String, dynamic>).cast<String, String>();
    } on FormatException {
      return {};
    }
  }

  Future<void> writeStringMap(String key, Map<String, String> value) => setString(key, jsonEncode(value));
}

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Overridden in main() with the already-initialized instance.
final sharedPrefsProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('sharedPrefsProvider must be overridden'),
);

final secureStoreProvider = Provider<SecureStore>((ref) => SecureStore(const FlutterSecureStorage()));

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
  static const pinnedRepos = 'pinned_repos';
  static const recentRepos = 'recent_repos';
  static const offlineModeRepos = 'offline_mode_repos';
  static const customCommands = 'custom_commands';
  static const sshHosts = 'ssh_hosts';
  static const knownHosts = 'known_hosts';
  static const diffWrap = 'diff_wrap';
  static const diffFontSize = 'diff_wrap_font';
  static const splitCollapsed = 'split_collapsed';
}

class SecureStore {
  SecureStore(this._storage);
  final FlutterSecureStorage _storage;

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

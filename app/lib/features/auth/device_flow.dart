import 'dart:async';

import 'package:dio/dio.dart';

/// Diffcat's OAuth App client ID. Public by design (the device flow has no
/// secret), so it ships in the code like other open-source GitHub clients.
/// Forks register their own app and pass `--dart-define=GITHUB_CLIENT_ID=…`
/// (SETUP.md § 1b); an empty value hides "Sign in with GitHub".
const githubClientId = String.fromEnvironment('GITHUB_CLIENT_ID', defaultValue: 'Ov23liRYJOTAGbpb8MDU');

/// Scopes asked for: `repo` to read private repos and submit reviews,
/// `read:user` for the account name.
const deviceFlowScopes = 'repo read:user';

/// What to show the user while they approve on github.com.
class DeviceCode {
  const DeviceCode({
    required this.deviceCode,
    required this.userCode,
    required this.verificationUri,
    required this.expiresAt,
    required this.interval,
  });

  final String deviceCode;

  /// Typed on github.com/login/device, e.g. `WDJB-MJHT`.
  final String userCode;
  final String verificationUri;
  final DateTime expiresAt;
  final Duration interval;
}

class DeviceFlowException implements Exception {
  const DeviceFlowException(this.message, {this.network = false});
  final String message;

  /// GitHub couldn't be reached (no response at all).
  final bool network;

  @override
  String toString() => message;
}

/// GitHub's OAuth device flow: no client secret, no redirect, no backend.
/// https://docs.github.com/apps/oauth-apps/building-oauth-apps/authorizing-oauth-apps#device-flow
class DeviceFlow {
  DeviceFlow({required this.clientId, Dio? dio, DateTime Function()? clock, this.sleep = Future<void>.delayed})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: 'https://github.com',
              headers: {'Accept': 'application/json'},
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 30),
            ),
          ),
      _now = clock ?? DateTime.now;

  final String clientId;
  final Dio _dio;
  final DateTime Function() _now;

  /// Waits between polls (replaced in tests).
  final Future<void> Function(Duration) sleep;

  bool _cancelled = false;
  Completer<void>? _wake;

  void cancel() {
    _cancelled = true;
    pollNow();
  }

  /// Ends the current wait and asks GitHub right away, e.g. when the user
  /// comes back to the app after approving in the browser.
  void pollNow() {
    final wake = _wake;
    if (wake != null && !wake.isCompleted) wake.complete();
  }

  Future<void> _wait(Duration d) {
    final wake = _wake = Completer<void>();
    return Future.any([sleep(d), wake.future]);
  }

  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body) async {
    try {
      final res = await _dio.post<dynamic>(
        path,
        data: body,
        options: Options(contentType: Headers.jsonContentType),
      );
      return res.data is Map<String, dynamic> ? res.data as Map<String, dynamic> : const {};
    } on DioException catch (e) {
      throw DeviceFlowException("Couldn't reach GitHub: ${e.message ?? e.type.name}", network: e.response == null);
    }
  }

  Future<DeviceCode> start({String scope = deviceFlowScopes}) async {
    final j = await _post('/login/device/code', {'client_id': clientId, 'scope': scope});
    if (j['device_code'] == null) {
      throw DeviceFlowException(
        (j['error_description'] as String?) ?? 'GitHub refused to start sign-in (is Device Flow enabled for the app?)',
      );
    }
    return DeviceCode(
      deviceCode: j['device_code'] as String,
      userCode: j['user_code'] as String,
      verificationUri: (j['verification_uri'] as String?) ?? 'https://github.com/login/device',
      expiresAt: _now().add(Duration(seconds: (j['expires_in'] as int?) ?? 900)),
      interval: Duration(seconds: (j['interval'] as int?) ?? 5),
    );
  }

  /// Polls until the user approves (returns the token), denies, the code
  /// expires, or [cancel] is called (throws [DeviceFlowException]).
  ///
  /// Not reaching GitHub doesn't end it: while the user approves in the
  /// browser, Android cuts a background app's network, so a poll fails with
  /// "Failed host lookup". It keeps trying until the code expires.
  Future<String> waitForToken(DeviceCode code) async {
    var interval = code.interval;
    DeviceFlowException? offline;
    while (true) {
      await _wait(interval);
      if (_cancelled) throw const DeviceFlowException('Cancelled');
      if (_now().isAfter(code.expiresAt)) {
        throw DeviceFlowException('The code expired. Start again.${offline == null ? '' : ' (${offline.message})'}');
      }
      final Map<String, dynamic> j;
      try {
        j = await _post('/login/oauth/access_token', {
          'client_id': clientId,
          'device_code': code.deviceCode,
          'grant_type': 'urn:ietf:params:oauth:grant-type:device_code',
        });
      } on DeviceFlowException catch (e) {
        if (!e.network) rethrow;
        offline = e;
        continue;
      }
      offline = null;
      if (j['access_token'] case final String token) return token;
      switch (j['error']) {
        case 'authorization_pending':
          continue;
        case 'slow_down':
          // GitHub says how long to wait now; otherwise add 5 s as the spec asks.
          interval = Duration(seconds: (j['interval'] as int?) ?? interval.inSeconds + 5);
        case 'expired_token':
          throw const DeviceFlowException('The code expired. Start again.');
        case 'access_denied':
          throw const DeviceFlowException('Sign-in was cancelled on GitHub.');
        default:
          throw DeviceFlowException((j['error_description'] as String?) ?? 'Sign-in failed (${j['error']}).');
      }
    }
  }
}

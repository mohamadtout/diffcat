import 'package:dio/dio.dart';

/// The OAuth App's client ID (public, not a secret). Set at build time:
/// `--dart-define=GITHUB_CLIENT_ID=Ov23…` (see SETUP.md § 2). Empty: the
/// "Sign in with GitHub" button is hidden and tokens are pasted instead.
const githubClientId = String.fromEnvironment('GITHUB_CLIENT_ID');

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
  const DeviceFlowException(this.message);
  final String message;

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

  void cancel() => _cancelled = true;

  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body) async {
    try {
      final res = await _dio.post<dynamic>(
        path,
        data: body,
        options: Options(contentType: Headers.jsonContentType),
      );
      return res.data is Map<String, dynamic> ? res.data as Map<String, dynamic> : const {};
    } on DioException catch (e) {
      throw DeviceFlowException("Couldn't reach GitHub: ${e.message ?? e.type.name}");
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
  Future<String> waitForToken(DeviceCode code) async {
    var interval = code.interval;
    while (true) {
      await sleep(interval);
      if (_cancelled) throw const DeviceFlowException('Cancelled');
      if (_now().isAfter(code.expiresAt)) throw const DeviceFlowException('The code expired. Start again.');
      final j = await _post('/login/oauth/access_token', {
        'client_id': clientId,
        'device_code': code.deviceCode,
        'grant_type': 'urn:ietf:params:oauth:grant-type:device_code',
      });
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

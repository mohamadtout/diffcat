import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:git_reviewer/app.dart';
import 'package:git_reviewer/core/storage/storage.dart';
import 'package:git_reviewer/data/github/models/models.dart';
import 'package:git_reviewer/features/auth/auth_controller.dart';
import 'package:git_reviewer/features/auth/device_flow.dart';
import 'package:git_reviewer/features/auth/token_screen.dart';
import 'package:git_reviewer/features/repos/repos_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Answers the device code request, then [polls] in order (last one repeats).
class _GitHubLogin implements HttpClientAdapter {
  _GitHubLogin(this.polls);

  final List<Map<String, Object>> polls;
  final bodies = <Map<String, dynamic>>[];

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? _, Future<void>? _) async {
    bodies.add(o.data as Map<String, dynamic>);
    if (o.path != '/login/device/code' && polls.first.containsKey('offline')) {
      polls.removeAt(0);
      // What a backgrounded Android app gets: no network, no DNS.
      throw DioException.connectionError(requestOptions: o, reason: "Failed host lookup: 'github.com'");
    }
    final Map<String, Object> body = o.path == '/login/device/code'
        ? {
            'device_code': 'dev123',
            'user_code': 'WDJB-MJHT',
            'verification_uri': 'https://github.com/login/device',
            'expires_in': 900,
            'interval': 5,
          }
        : (polls.length > 1 ? polls.removeAt(0) : polls.first);
    return ResponseBody.fromString(
      jsonEncode(body),
      200,
      headers: {
        'content-type': ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

DeviceFlow _flow(_GitHubLogin server, {List<Duration>? waits, DateTime Function()? clock}) => DeviceFlow(
  clientId: 'Ov23test',
  dio: Dio(BaseOptions(baseUrl: 'https://github.com'))..httpClientAdapter = server,
  clock: clock,
  sleep: (d) async => waits?.add(d),
);

void main() {
  test('polls through pending and slow_down until the token arrives', () async {
    final server = _GitHubLogin([
      {'error': 'authorization_pending'},
      {'error': 'slow_down', 'interval': 10},
      {'access_token': 'gho_abc', 'token_type': 'bearer'},
    ]);
    final waits = <Duration>[];
    final flow = _flow(server, waits: waits);
    final code = await flow.start();
    expect(code.userCode, 'WDJB-MJHT');
    expect(await flow.waitForToken(code), 'gho_abc');
    expect(waits, const [Duration(seconds: 5), Duration(seconds: 5), Duration(seconds: 10)]);
    expect(server.bodies.first, {'client_id': 'Ov23test', 'scope': deviceFlowScopes});
    expect(server.bodies.last['grant_type'], 'urn:ietf:params:oauth:grant-type:device_code');
    expect(server.bodies.last['device_code'], 'dev123');
  });

  test('losing the network while the user approves in the browser keeps it waiting', () async {
    final server = _GitHubLogin([
      {'error': 'authorization_pending'},
      {'offline': true},
      {'offline': true},
      {'access_token': 'gho_back', 'token_type': 'bearer'},
    ]);
    final flow = _flow(server);
    expect(await flow.waitForToken(await flow.start()), 'gho_back');

    // A GitHub error with a response still ends it.
    final refused = _flow(
      _GitHubLogin([
        {'error': 'incorrect_client_credentials', 'error_description': 'Bad client'},
      ]),
    );
    await expectLater(refused.waitForToken(await refused.start()), throwsA(predicate((e) => '$e' == 'Bad client')));
  });

  test('pollNow asks GitHub right away instead of finishing the wait', () async {
    final server = _GitHubLogin([
      {'access_token': 'gho_now', 'token_type': 'bearer'},
    ]);
    final flow = DeviceFlow(
      clientId: 'Ov23test',
      dio: Dio(BaseOptions(baseUrl: 'https://github.com'))..httpClientAdapter = server,
      sleep: (_) => Completer<void>().future, // a wait that never ends on its own
    );
    final token = flow.waitForToken(await flow.start());
    await Future<void>.delayed(Duration.zero);
    flow.pollNow();
    expect(await token, 'gho_now');
  });

  test('denied, expired and cancelled sign-ins stop with a message', () async {
    Future<String> run(Map<String, Object> answer) async {
      final flow = _flow(_GitHubLogin([answer]));
      return flow.waitForToken(await flow.start());
    }

    await expectLater(run({'error': 'access_denied'}), throwsA(isA<DeviceFlowException>()));
    await expectLater(run({'error': 'expired_token'}), throwsA(isA<DeviceFlowException>()));

    var now = DateTime(2026);
    final late = _flow(
      _GitHubLogin([
        {'error': 'authorization_pending'},
      ]),
      clock: () => now,
    );
    final code = await late.start();
    now = now.add(const Duration(hours: 1));
    await expectLater(late.waitForToken(code), throwsA(predicate((e) => '$e'.contains('expired'))));

    final cancelled = _flow(
      _GitHubLogin([
        {'error': 'authorization_pending'},
      ]),
    );
    final c2 = await cancelled.start();
    cancelled.cancel();
    await expectLater(cancelled.waitForToken(c2), throwsA(predicate((e) => '$e' == 'Cancelled')));
  });

  testWidgets('"Sign in with GitHub" shows the code and signs in with the approved token', (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    String? validated;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPrefsProvider.overrideWithValue(prefs),
          tokenValidatorProvider.overrideWithValue((t) async {
            validated = t;
            return const GhUser(login: 'me');
          }),
          myReposProvider.overrideWith((ref) async => <GhRepo>[]),
          viewerProvider.overrideWith((ref) async => const GhUser(login: 'me')),
          deviceFlowProvider.overrideWithValue(
            () => _flow(
              _GitHubLogin([
                {'error': 'authorization_pending'},
                {'access_token': 'gho_ok'},
              ]),
            ),
          ),
        ],
        child: const GitReviewerApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign in for your own and private repos'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Sign in with GitHub'));
    await tester.pumpAndSettle();
    expect(validated, 'gho_ok');
    expect(find.byType(TokenScreen), findsNothing);
    expect(find.text('Filter repositories'), findsOneWidget);
  });

  testWidgets('the dialog shows the code to enter, and Cancel stops polling', (tester) async {
    // Real (fake-clock) waits between polls, so the dialog stays up.
    final flow = DeviceFlow(
      clientId: 'Ov23test',
      dio: Dio(BaseOptions(baseUrl: 'https://github.com'))
        ..httpClientAdapter = _GitHubLogin([
          {'error': 'authorization_pending'},
        ]),
    );
    String? result = 'unset';
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => result = await showDialog<String>(
              context: context,
              builder: (_) => DeviceCodeDialog(flow: flow),
            ),
            child: const Text('go'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('WDJB-MJHT'), findsOneWidget);
    expect(find.text('Open GitHub'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(result, isNull);
    // The poll that was waiting wakes up, sees the cancel and stops.
    await tester.pump(const Duration(seconds: 6));
  });
}

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:git_reviewer/core/storage/storage.dart';
import 'package:git_reviewer/features/auth/auth_controller.dart';
import 'package:git_reviewer/features/notifications/watch_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// GitHub with nothing in it: every list is empty.
class _EmptyGitHub implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString(
    '[]',
    200,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );

  @override
  void close({bool force = false}) {}
}

Future<ProviderContainer> _container(Map<String, Object> prefs) async {
  SharedPreferences.setMockInitialValues(prefs);
  FlutterSecureStorage.setMockInitialValues({StoreKeys.githubToken: 'token'});
  final container = ProviderContainer(
    overrides: [
      sharedPrefsProvider.overrideWithValue(await SharedPreferences.getInstance()),
      githubAdapterProvider.overrideWithValue(_EmptyGitHub()),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  test('restore puts back the watched repos (Undo after hiding)', () async {
    final container = await _container({
      StoreKeys.watchedRepos: ['o/a', 'o/b'],
    });
    final watched = container.read(watchedReposProvider.notifier);
    final before = container.read(watchedReposProvider);
    await watched.unwatchAll({'o/a'});
    expect(container.read(watchedReposProvider), {'o/b'});
    await watched.restore(before);
    expect(container.read(watchedReposProvider), {'o/a', 'o/b'});
    expect((await SharedPreferences.getInstance()).getStringList(StoreKeys.watchedRepos), ['o/a', 'o/b']);
  });

  test('opening the app checks even though the token is still being read', () async {
    final container = await _container({
      StoreKeys.watchedRepos: ['o/a'],
    });
    expect(container.read(authTokenProvider).isLoading, isTrue);
    expect(await container.read(pollControllerProvider.notifier).checkIfStale(), isTrue);
    expect(container.read(pollControllerProvider).last, isNotNull);
  });
}

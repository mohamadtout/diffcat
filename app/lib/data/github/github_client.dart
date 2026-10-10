import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'etag_cache.dart';
import 'github_exception.dart';
import 'response_cache.dart';

/// One page of a paginated GitHub list endpoint.
class GhPage<T> {
  const GhPage(this.items, {required this.hasNext, this.lastPage});

  final List<T> items;
  final bool hasNext;

  /// Number of the last page (from `Link: rel="last"`), when there's more
  /// than one. With `per_page=1` it's the total count.
  final int? lastPage;
}

/// Low-level HTTP client for the GitHub REST API.
///
/// Responsibilities:
/// - auth + API version headers
/// - conditional requests (ETag / If-None-Match) so repeated reads of the same
///   resource return 304 and do not count against the rate limit
/// - mapping failures to [GitHubException]
///
/// [token] is optional: without it, public repos still work but GitHub allows
/// only 60 requests/hour instead of 5,000.
class GitHubClient {
  GitHubClient({
    String? token,
    Dio? dio,
    this.cache,
    this.cacheMode = CacheMode.replay,
    this.cacheOnly,
    this.preferSaved,
    this.etags,
  }) : isAnonymous = token == null,
       _dio = dio ?? Dio(baseOptions(token));

  /// Offline copies (features/offline). Null: network only.
  final ResponseCache? cache;

  /// ETags that outlive this client (the background check). The in-memory
  /// cache is consulted first.
  final EtagCache? etags;
  final CacheMode cacheMode;

  /// For keys where this returns true (repos in offline mode), only saved
  /// responses are used: anything else fails with
  /// [GitHubException.notDownloaded] and never touches the network.
  final bool Function(String key)? cacheOnly;

  /// For keys where this returns false, the network is asked first and a
  /// saved response is only the fallback when GitHub can't be reached (or the
  /// rate limit is used up). Null: saved responses always come first.
  final bool Function(String key)? preferSaved;

  /// Identifies a GET for caching. Offline downloads use it to file responses
  /// under exactly the key a later read will look up.
  /// GitHub treats owner/name case-insensitively, so keys do too.
  static String cacheKey(String path, {Map<String, dynamic>? query, String? accept}) =>
      '${accept ?? ''}|${path.replaceFirstMapped(_repoPrefix, (m) => m[0]!.toLowerCase())}?${_canonicalQuery(query)}';

  static final _repoPrefix = RegExp(r'^/repos/[^/]+/[^/]+');

  /// Accept header for raw file contents; part of their cache key.
  static const rawAccept = 'application/vnd.github.raw+json';

  /// Signed out ([token] null) sends no Authorization header at all.
  static BaseOptions baseOptions(String? token) => BaseOptions(
    baseUrl: 'https://api.github.com',
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 30),
    headers: {
      'Accept': 'application/vnd.github+json',
      'X-GitHub-Api-Version': '2022-11-28',
      'Authorization': ?(token == null ? null : 'Bearer $token'),
    },
    validateStatus: (s) => s != null && (s < 300 || s == 304),
  );

  final Dio _dio;

  /// Signed out: lower rate limit and public repos only.
  final bool isAnonymous;
  final Map<String, _CacheEntry> _cache = {};
  static const _maxCacheEntries = 300;

  /// Seconds GitHub asks pollers to wait (`X-Poll-Interval`, sent by the
  /// notifications endpoint), from the latest response that had it.
  int? pollInterval;

  /// Last known rate limit state, updated on every response.
  int? rateLimitRemaining;
  DateTime? rateLimitReset;

  Future<dynamic> getJson(String path, {Map<String, dynamic>? query}) async {
    final res = await _get(path, query: query);
    return res.data;
  }

  /// Fetches one page and reports whether the `Link` header has a next page.
  Future<GhPage<T>> getPage<T>(
    String path, {
    Map<String, dynamic>? query,
    required T Function(Map<String, dynamic>) parse,
  }) async {
    final res = await _get(path, query: query);
    final list = (res.data as List<dynamic>).cast<Map<String, dynamic>>();
    final link = res.headers.value('link') ?? '';
    final last = RegExp(r'[?&]page=(\d+)[^>]*>;\s*rel="last"').firstMatch(link);
    return GhPage(
      list.map(parse).toList(),
      hasNext: link.contains('rel="next"'),
      lastPage: last == null ? null : int.parse(last[1]!),
    );
  }

  /// Fetches consecutive pages until exhausted or [maxPages] is reached.
  Future<List<T>> getAll<T>(
    String path, {
    Map<String, dynamic>? query,
    required T Function(Map<String, dynamic>) parse,
    int perPage = 100,
    int maxPages = 10,
  }) async {
    final out = <T>[];
    for (var page = 1; page <= maxPages; page++) {
      final p = await getPage(path, query: {...?query, 'per_page': perPage, 'page': page}, parse: parse);
      out.addAll(p.items);
      if (!p.hasNext) break;
    }
    return out;
  }

  /// Raw file contents (bypasses base64 JSON wrapping).
  Future<String> getRaw(String path, {Map<String, dynamic>? query}) async {
    final res = await _get(path, query: query, accept: rawAccept, responseType: ResponseType.plain);
    return res.data as String;
  }

  /// Binary download (e.g. a tarball). Never cached; follows GitHub's redirect
  /// (Dart drops the Authorization header when it leaves api.github.com).
  ///
  /// Streams, and stops at [maxBytes]: a huge repo's archive would otherwise
  /// be held in memory whole and could take the app down.
  Future<List<int>> getBytes(String path, {int maxBytes = 300 * 1000 * 1000}) async {
    try {
      final res = await _dio.get<ResponseBody>(path, options: Options(responseType: ResponseType.stream));
      _trackRateLimit(res.headers);
      final body = res.data;
      if (body == null) return const [];
      final out = BytesBuilder(copy: false);
      await for (final chunk in body.stream) {
        out.add(chunk);
        if (out.length > maxBytes) {
          throw GitHubException('Download larger than ${maxBytes ~/ 1000000} MB, stopped.');
        }
      }
      return out.takeBytes();
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  Future<dynamic> postJson(String path, Map<String, dynamic> body) async {
    try {
      final res = await _dio.post<dynamic>(path, data: body);
      _trackRateLimit(res.headers);
      return res.data;
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  Future<Response<dynamic>> _get(
    String path, {
    Map<String, dynamic>? query,
    String? accept,
    ResponseType? responseType,
  }) async {
    final key = cacheKey(path, query: query, accept: accept);
    final replay = cacheMode == CacheMode.replay && cache != null;
    final only = replay && (cacheOnly?.call(key) ?? false);
    final savedFirst = only || (replay && (preferSaved?.call(key) ?? true));
    Response<dynamic> fromSaved(CachedResponse saved) => Response(
      requestOptions: RequestOptions(path: path, queryParameters: query),
      statusCode: 200,
      data: saved.data,
      headers: Headers.fromMap({
        if (saved.link != null) 'link': [saved.link!],
      }),
    );
    if (savedFirst) {
      if (await cache!.read(key) case final saved?) return fromSaved(saved);
    }
    if (only) throw GitHubException.notDownloaded();
    var cached = _cache[key];
    if (cached == null && etags != null) {
      final stored = await etags!.read(key);
      if (stored != null) {
        cached = _CacheEntry(
          stored.etag,
          Response(
            requestOptions: RequestOptions(path: path, queryParameters: query),
            statusCode: 200,
            data: stored.data,
            headers: Headers.fromMap({
              if (stored.link != null) 'link': [stored.link!],
            }),
          ),
        );
      }
    }
    try {
      final res = await _dio.get<dynamic>(
        path,
        queryParameters: query,
        options: Options(responseType: responseType, headers: {'Accept': ?accept, 'If-None-Match': ?cached?.etag}),
      );
      _trackRateLimit(res.headers);
      if (res.statusCode == 304 && cached != null) return cached.response;
      final etag = res.headers.value('etag');
      if (etag != null) {
        _remember(key, _CacheEntry(etag, res));
        await etags?.write(key, EtagEntry(etag: etag, data: res.data, link: res.headers.value('link')));
      }
      if (cacheMode == CacheMode.record) {
        await cache?.write(key, path, query, CachedResponse(data: res.data, link: res.headers.value('link')));
      }
      return res;
    } on DioException catch (e) {
      final error = _mapError(e);
      // Fresh data was asked for but can't be had: the saved copy beats an error.
      if (replay && !savedFirst && (error.statusCode == null || error.isRateLimited)) {
        if (await cache!.read(key) case final saved?) return fromSaved(saved);
      }
      throw error;
    }
  }

  void _remember(String key, _CacheEntry entry) {
    _cache.remove(key);
    _cache[key] = entry;
    if (_cache.length > _maxCacheEntries) _cache.remove(_cache.keys.first);
  }

  static String _canonicalQuery(Map<String, dynamic>? q) {
    if (q == null || q.isEmpty) return '';
    final keys = q.keys.toList()..sort();
    return keys.map((k) => '$k=${q[k]}').join('&');
  }

  void _trackRateLimit(Headers h) {
    pollInterval = int.tryParse(h.value('x-poll-interval') ?? '') ?? pollInterval;
    final remaining = int.tryParse(h.value('x-ratelimit-remaining') ?? '');
    final reset = int.tryParse(h.value('x-ratelimit-reset') ?? '');
    if (remaining != null) rateLimitRemaining = remaining;
    if (reset != null) {
      rateLimitReset = DateTime.fromMillisecondsSinceEpoch(reset * 1000);
    }
  }

  GitHubException _mapError(DioException e) {
    final res = e.response;
    if (res == null) {
      return GitHubException('Network error: ${e.message ?? e.type.name}');
    }
    _trackRateLimit(res.headers);
    final data = res.data;
    final msg = data is Map && data['message'] is String ? data['message'] as String : 'GitHub request failed';
    final status = res.statusCode;
    final limited = (status == 403 || status == 429) && rateLimitRemaining == 0;
    return GitHubException(
      limited
          ? isAnonymous
                ? 'GitHub allows 60 requests an hour without signing in, and they are used up. '
                      'Sign in (Settings) for 5,000 an hour.'
                : 'GitHub rate limit exceeded'
          : msg,
      statusCode: status,
      rateLimitResetAt: limited ? rateLimitReset : null,
    );
  }
}

class _CacheEntry {
  _CacheEntry(this.etag, this.response);
  final String etag;
  final Response<dynamic> response;
}

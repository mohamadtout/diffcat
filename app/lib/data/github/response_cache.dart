/// Persistent store for GitHub responses (implemented by features/offline).
///
/// The client talks to it in one of two modes, see [CacheMode].
abstract interface class ResponseCache {
  Future<CachedResponse?> read(String key);
  Future<void> write(String key, String path, Map<String, dynamic>? query, CachedResponse response);
}

enum CacheMode {
  /// Serve saved responses when present, otherwise use the network. Used by the UI.
  replay,

  /// Always use the network and save every response. Used by downloads.
  record,
}

/// A saved response: the decoded body (JSON or raw text) plus the `Link`
/// header, which pagination needs.
class CachedResponse {
  const CachedResponse({required this.data, this.link});

  final Object? data;
  final String? link;
}

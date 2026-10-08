/// Error raised by [GitHubClient] for any non-successful GitHub API call.
class GitHubException implements Exception {
  GitHubException(this.message, {this.statusCode, this.rateLimitResetAt, this.notDownloaded = false});

  /// Offline mode asked for something that was never downloaded.
  GitHubException.notDownloaded()
    : this('Not downloaded. Switch this repo to online mode to load it.', notDownloaded: true);

  final String message;
  final int? statusCode;

  /// Set when the request failed because the rate limit was exhausted.
  final DateTime? rateLimitResetAt;

  bool get isUnauthorized => statusCode == 401;
  bool get isNotFound => statusCode == 404;
  bool get isRateLimited => rateLimitResetAt != null;
  final bool notDownloaded;

  /// Network errors and 5xx responses are worth retrying; 4xx and missing
  /// offline data are not.
  bool get isRetryable => !notDownloaded && (statusCode == null || statusCode! >= 500);

  @override
  String toString() => statusCode == null ? message : '$message ($statusCode)';
}

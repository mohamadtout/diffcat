import 'repo.dart';

/// A pull request as the search API returns it (an issue with PR fields).
class GhSearchPull {
  const GhSearchPull({
    required this.repo,
    required this.number,
    required this.title,
    required this.author,
    required this.updatedAt,
    this.draft = false,
    this.comments = 0,
  });

  factory GhSearchPull.fromJson(Map<String, dynamic> j) {
    // https://api.github.com/repos/<owner>/<name>
    final parts = Uri.parse(j['repository_url'] as String).pathSegments;
    return GhSearchPull(
      repo: (owner: parts[parts.length - 2], name: parts.last),
      number: j['number'] as int,
      title: (j['title'] as String?) ?? '',
      author: GhUser.fromJson(j['user'] as Map<String, dynamic>),
      updatedAt: DateTime.tryParse((j['updated_at'] as String?) ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0),
      draft: (j['draft'] as bool?) ?? false,
      comments: (j['comments'] as int?) ?? 0,
    );
  }

  final RepoRef repo;
  final int number;
  final String title;
  final GhUser author;
  final DateTime updatedAt;
  final bool draft;
  final int comments;

  /// `owner/name#number`, lower-case owner/name (GitHub ignores their case).
  String get key => '${repo.fullName.toLowerCase()}#$number';
}

class GhSearchResult<T> {
  const GhSearchResult(this.items, {required this.total});

  final List<T> items;

  /// Matches in all (more than [items] when there are further pages).
  final int total;
}

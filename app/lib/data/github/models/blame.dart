/// Lines [start]..[end] (1-based, inclusive) last changed by one commit.
class BlameRange {
  const BlameRange({
    required this.start,
    required this.end,
    required this.age,
    required this.sha,
    required this.title,
    required this.authorName,
    required this.date,
    this.authorLogin,
  });

  factory BlameRange.fromJson(Map<String, dynamic> j) {
    final c = j['commit'] as Map<String, dynamic>;
    final author = c['author'] as Map<String, dynamic>?;
    return BlameRange(
      start: j['startingLine'] as int,
      end: j['endingLine'] as int,
      age: (j['age'] as int?) ?? 1,
      sha: c['oid'] as String,
      title: (c['messageHeadline'] as String?) ?? '',
      authorName: (author?['name'] as String?) ?? 'unknown',
      authorLogin: (author?['user'] as Map<String, dynamic>?)?['login'] as String?,
      date: DateTime.tryParse((c['committedDate'] as String?) ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  final int start;
  final int end;

  /// GitHub's recency bucket, 1 (newest) to 10 (oldest).
  final int age;
  final String sha;
  final String title;
  final String authorName;
  final String? authorLogin;
  final DateTime date;

  String get shortSha => sha.length > 7 ? sha.substring(0, 7) : sha;
}

/// The range covering each line of a file: `result[i]` is line i + 1's.
/// Lines no range covers (shouldn't happen) map to null.
List<BlameRange?> blameByLine(List<BlameRange> ranges, int lineCount) {
  final out = List<BlameRange?>.filled(lineCount, null);
  for (final r in ranges) {
    for (var l = r.start; l <= r.end && l <= lineCount; l++) {
      if (l >= 1) out[l - 1] = r;
    }
  }
  return out;
}

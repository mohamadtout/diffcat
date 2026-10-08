enum FileChangeStatus {
  added('A'),
  modified('M'),
  removed('D'),
  renamed('R'),
  copied('C'),
  changed('T'),
  unchanged('U');

  const FileChangeStatus(this.letter);
  final String letter;

  static FileChangeStatus parse(String? s) => switch (s) {
    'added' => added,
    'removed' => removed,
    'renamed' => renamed,
    'copied' => copied,
    'changed' => changed,
    'unchanged' => unchanged,
    _ => modified,
  };
}

/// A file entry in a commit, comparison or pull request.
class GhFileChange {
  const GhFileChange({
    required this.filename,
    required this.status,
    required this.additions,
    required this.deletions,
    this.previousFilename,
    this.patch,
    this.blobSha,
  });

  factory GhFileChange.fromJson(Map<String, dynamic> j) => GhFileChange(
    filename: j['filename'] as String,
    previousFilename: j['previous_filename'] as String?,
    status: FileChangeStatus.parse(j['status'] as String?),
    additions: (j['additions'] as int?) ?? 0,
    deletions: (j['deletions'] as int?) ?? 0,
    patch: j['patch'] as String?,
    blobSha: j['sha'] as String?,
  );

  final String filename;
  final String? previousFilename;
  final FileChangeStatus status;
  final int additions;
  final int deletions;

  /// Unified diff hunks. Null for binary files or diffs GitHub deems too large.
  final String? patch;
  final String? blobSha;

  String get basename => filename.split('/').last;
  String get directory {
    final i = filename.lastIndexOf('/');
    return i < 0 ? '' : filename.substring(0, i);
  }
}

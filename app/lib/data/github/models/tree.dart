enum TreeEntryType { blob, tree, submodule }

class GhTreeEntry {
  const GhTreeEntry({required this.path, required this.type, required this.sha, this.size});

  factory GhTreeEntry.fromJson(Map<String, dynamic> j) => GhTreeEntry(
    path: j['path'] as String,
    type: switch (j['type']) {
      'tree' => TreeEntryType.tree,
      'commit' => TreeEntryType.submodule,
      _ => TreeEntryType.blob,
    },
    sha: j['sha'] as String,
    size: j['size'] as int?,
  );

  final String path;
  final TreeEntryType type;
  final String sha;
  final int? size;
}

class GhTree {
  const GhTree({required this.sha, required this.entries, required this.truncated});

  factory GhTree.fromJson(Map<String, dynamic> j) => GhTree(
    sha: j['sha'] as String,
    truncated: (j['truncated'] as bool?) ?? false,
    entries: [for (final e in (j['tree'] as List<dynamic>)) GhTreeEntry.fromJson(e as Map<String, dynamic>)],
  );

  final String sha;
  final List<GhTreeEntry> entries;

  /// True when the repo is too large for a single recursive tree response.
  final bool truncated;
}

/// Identifies a repository. Used as provider family key and in routes.
typedef RepoRef = ({String owner, String name});

extension RepoRefX on RepoRef {
  String get fullName => '$owner/$name';
}

class GhUser {
  const GhUser({required this.login, this.avatarUrl, this.name});

  factory GhUser.fromJson(Map<String, dynamic> j) =>
      GhUser(login: j['login'] as String, avatarUrl: j['avatar_url'] as String?, name: j['name'] as String?);

  final String login;
  final String? avatarUrl;
  final String? name;
}

class GhRepo {
  const GhRepo({
    required this.owner,
    required this.name,
    required this.defaultBranch,
    required this.isPrivate,
    this.description,
    this.language,
    this.pushedAt,
    this.ownerAvatarUrl,
  });

  factory GhRepo.fromJson(Map<String, dynamic> j) {
    final owner = j['owner'] as Map<String, dynamic>;
    return GhRepo(
      owner: owner['login'] as String,
      ownerAvatarUrl: owner['avatar_url'] as String?,
      name: j['name'] as String,
      defaultBranch: (j['default_branch'] as String?) ?? 'main',
      isPrivate: (j['private'] as bool?) ?? false,
      description: j['description'] as String?,
      language: j['language'] as String?,
      pushedAt: DateTime.tryParse((j['pushed_at'] as String?) ?? ''),
    );
  }

  final String owner;
  final String name;
  final String defaultBranch;
  final bool isPrivate;
  final String? description;
  final String? language;
  final DateTime? pushedAt;
  final String? ownerAvatarUrl;

  RepoRef get ref => (owner: owner, name: name);
  String get fullName => '$owner/$name';
}

class GhBranch {
  const GhBranch({required this.name, required this.sha});

  factory GhBranch.fromJson(Map<String, dynamic> j) =>
      GhBranch(name: j['name'] as String, sha: (j['commit'] as Map<String, dynamic>)['sha'] as String);

  final String name;
  final String sha;
}

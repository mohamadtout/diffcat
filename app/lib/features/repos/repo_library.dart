import 'dart:convert';

import 'package:flutter/painting.dart';

import '../../data/github/models/models.dart';

/// Colors a folder can have: mid tones that read on light and dark.
const folderColors = [
  Color(0xFF8C959F), // grey
  Color(0xFFE5534B), // red
  Color(0xFFDB6D28), // orange
  Color(0xFFC69026), // yellow
  Color(0xFF3FB950), // green
  Color(0xFF39C5CF), // teal
  Color(0xFF4493F8), // blue
  Color(0xFFAB7DF8), // purple
  Color(0xFFDB61A2), // pink
];

/// A user's folder of repos in the repo list.
class RepoFolder {
  const RepoFolder({required this.id, required this.name, required this.color, this.collapsed = false});

  factory RepoFolder.fromJson(Map<String, dynamic> j) => RepoFolder(
    id: j['id'] as String,
    name: j['name'] as String,
    color: Color((j['color'] as int?) ?? folderColors.first.toARGB32()),
    collapsed: (j['collapsed'] as bool?) ?? false,
  );

  final String id;
  final String name;
  final Color color;
  final bool collapsed;

  RepoFolder copyWith({String? name, Color? color, bool? collapsed}) =>
      RepoFolder(id: id, name: name ?? this.name, color: color ?? this.color, collapsed: collapsed ?? this.collapsed);

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'color': color.toARGB32(), 'collapsed': collapsed};
}

enum RepoSort { pushed, name }

/// Which repos the list asks GitHub for (`affiliation` of `GET /user/repos`).
/// Kinds turned off are never requested.
class RepoSources {
  const RepoSources({this.owned = true, this.collaborations = true, this.organizations = true});

  factory RepoSources.fromJson(Map<String, dynamic> j) => RepoSources(
    owned: (j['owned'] as bool?) ?? true,
    collaborations: (j['collaborations'] as bool?) ?? true,
    organizations: (j['organizations'] as bool?) ?? true,
  );

  final bool owned;
  final bool collaborations;
  final bool organizations;

  /// The `affiliation` query value; empty when everything is off.
  String get affiliation =>
      [if (owned) 'owner', if (collaborations) 'collaborator', if (organizations) 'organization_member'].join(',');

  RepoSources copyWith({bool? owned, bool? collaborations, bool? organizations}) => RepoSources(
    owned: owned ?? this.owned,
    collaborations: collaborations ?? this.collaborations,
    organizations: organizations ?? this.organizations,
  );

  @override
  bool operator ==(Object other) => other is RepoSources && other.affiliation == affiliation;

  @override
  int get hashCode => affiliation.hashCode;

  Map<String, dynamic> toJson() => {'owned': owned, 'collaborations': collaborations, 'organizations': organizations};
}

/// How the user organized their repo list: folders, archived and hidden repos,
/// hidden accounts, which repos to load, and the sort order. Repos are keyed by
/// lower-case `owner/name`, accounts by lower-case login (GitHub ignores case).
///
/// - **Archived** repos move to a collapsed section at the bottom. Repos
///   archived on GitHub go there too, unless the user unarchived them here.
/// - **Hidden** repos and accounts are never shown, watched, or reported in
///   notifications or the inbox.
class RepoLibrary {
  const RepoLibrary({
    this.folders = const [],
    this.folderOf = const {},
    this.archived = const {},
    this.unarchived = const {},
    this.hidden = const {},
    this.hiddenOwners = const {},
    this.sources = const RepoSources(),
    this.sort = RepoSort.pushed,
    this.archivedCollapsed = true,
  });

  factory RepoLibrary.fromJson(Map<String, dynamic> j) {
    Set<String> set(Object? v) => {if (v is List) ...v.whereType<String>()};
    final folders = [
      if (j['folders'] case final List<dynamic> list)
        for (final f in list)
          if (f is Map<String, dynamic>) RepoFolder.fromJson(f),
    ];
    final ids = {for (final f in folders) f.id};
    return RepoLibrary(
      folders: folders,
      folderOf: {
        if (j['folderOf'] case final Map<String, dynamic> m)
          for (final e in m.entries)
            if (e.value is String && ids.contains(e.value)) e.key: e.value as String,
      },
      archived: set(j['archived']),
      unarchived: set(j['unarchived']),
      hidden: set(j['hidden']),
      hiddenOwners: set(j['hiddenOwners']),
      sources: j['sources'] is Map<String, dynamic>
          ? RepoSources.fromJson(j['sources'] as Map<String, dynamic>)
          : const RepoSources(),
      sort: RepoSort.values.asNameMap()[j['sort']] ?? RepoSort.pushed,
      archivedCollapsed: (j['archivedCollapsed'] as bool?) ?? true,
    );
  }

  static RepoLibrary parse(String? raw) {
    if (raw == null) return const RepoLibrary();
    try {
      return RepoLibrary.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on Object {
      return const RepoLibrary(); // unreadable: start over rather than lose the repo list
    }
  }

  final List<RepoFolder> folders;

  /// Repo → folder id. Repos without one are in "Other".
  final Map<String, String> folderOf;
  final Set<String> archived;

  /// Repos archived on GitHub that the user keeps with the active ones.
  final Set<String> unarchived;
  final Set<String> hidden;
  final Set<String> hiddenOwners;
  final RepoSources sources;
  final RepoSort sort;
  final bool archivedCollapsed;

  static String key(String fullName) => fullName.toLowerCase();

  bool isHidden(String fullName) =>
      hidden.contains(key(fullName)) || hiddenOwners.contains(key(fullName.split('/').first));

  bool isArchived(GhRepo r) {
    final k = key(r.fullName);
    return archived.contains(k) || (r.archived && !unarchived.contains(k));
  }

  RepoFolder? folderFor(String fullName) {
    final id = folderOf[key(fullName)];
    return id == null ? null : folders.where((f) => f.id == id).firstOrNull;
  }

  RepoLibrary copyWith({
    List<RepoFolder>? folders,
    Map<String, String>? folderOf,
    Set<String>? archived,
    Set<String>? unarchived,
    Set<String>? hidden,
    Set<String>? hiddenOwners,
    RepoSources? sources,
    RepoSort? sort,
    bool? archivedCollapsed,
  }) => RepoLibrary(
    folders: folders ?? this.folders,
    folderOf: folderOf ?? this.folderOf,
    archived: archived ?? this.archived,
    unarchived: unarchived ?? this.unarchived,
    hidden: hidden ?? this.hidden,
    hiddenOwners: hiddenOwners ?? this.hiddenOwners,
    sources: sources ?? this.sources,
    sort: sort ?? this.sort,
    archivedCollapsed: archivedCollapsed ?? this.archivedCollapsed,
  );

  // Folders

  RepoLibrary withFolder(RepoFolder folder) => copyWith(
    folders: folders.any((f) => f.id == folder.id)
        ? [for (final f in folders) f.id == folder.id ? folder : f]
        : [...folders, folder],
  );

  /// Deletes a folder; its repos go back to "Other".
  RepoLibrary withoutFolder(String id) => copyWith(
    folders: [
      for (final f in folders)
        if (f.id != id) f,
    ],
    folderOf: {
      for (final e in folderOf.entries)
        if (e.value != id) e.key: e.value,
    },
  );

  /// Moves the folder at [from] to index [to] (its final position).
  /// Indexes out of range are clamped, so moving the first folder up does nothing.
  RepoLibrary reorderFolder(int from, int to) {
    if (from < 0 || from >= folders.length) return this;
    final list = [...folders];
    list.insert(to.clamp(0, folders.length - 1), list.removeAt(from));
    return copyWith(folders: list);
  }

  RepoLibrary toggleCollapsed(String folderId) =>
      copyWith(folders: [for (final f in folders) f.id == folderId ? f.copyWith(collapsed: !f.collapsed) : f]);

  // Repos (each takes several, for bulk actions)

  /// Moves [repos] into [folderId] (null: out of any folder), and out of the
  /// archive: filing a repo means it's in use.
  RepoLibrary move(Iterable<GhRepo> repos, String? folderId) {
    final keys = {for (final r in repos) key(r.fullName)};
    return setArchived(repos, archive: false).copyWith(
      folderOf: {
        for (final e in folderOf.entries)
          if (!keys.contains(e.key)) e.key: e.value,
        if (folderId != null)
          for (final k in keys) k: folderId,
      },
    );
  }

  /// Archives or unarchives [repos]. Unarchiving a repo archived on GitHub
  /// keeps it with the active repos; archiving it again undoes that.
  RepoLibrary setArchived(Iterable<GhRepo> repos, {required bool archive}) {
    final keys = {for (final r in repos) key(r.fullName)};
    final onGitHub = {
      for (final r in repos)
        if (r.archived) key(r.fullName),
    };
    return archive
        ? copyWith(archived: archived.union(keys.difference(onGitHub)), unarchived: unarchived.difference(keys))
        : copyWith(archived: archived.difference(keys), unarchived: unarchived.union(onGitHub));
  }

  RepoLibrary setHidden(Iterable<String> repos, {required bool hide}) {
    final keys = repos.map(key).toSet();
    return copyWith(hidden: hide ? hidden.union(keys) : hidden.difference(keys));
  }

  RepoLibrary setOwnerHidden(String login, {required bool hide}) =>
      copyWith(hiddenOwners: hide ? {...hiddenOwners, key(login)} : ({...hiddenOwners}..remove(key(login))));

  /// The list's sections, in order. Hidden repos are left out; [query]
  /// (lower-case) keeps matching repos only, and drops empty sections.
  List<RepoSection> arrange(List<GhRepo> repos, {Set<String> pinned = const {}, String query = ''}) {
    final pins = pinned.map(key).toSet();
    final visible = repos.where((r) => !isHidden(r.fullName)).where((r) => query.isEmpty || matches(r, query)).toList()
      ..sort(
        sort == RepoSort.name
            ? (a, b) => a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase())
            : (a, b) => (b.pushedAt ?? DateTime(0)).compareTo(a.pushedAt ?? DateTime(0)),
      );
    final pinnedRepos = <GhRepo>[];
    final byFolder = {for (final f in folders) f.id: <GhRepo>[]};
    final other = <GhRepo>[];
    final archivedRepos = <GhRepo>[];
    for (final r in visible) {
      if (isArchived(r)) {
        archivedRepos.add(r);
      } else if (pins.contains(key(r.fullName))) {
        pinnedRepos.add(r);
      } else if (byFolder[folderOf[key(r.fullName)]] case final list?) {
        list.add(r);
      } else {
        other.add(r);
      }
    }
    final searching = query.isNotEmpty;
    return [
      if (pinnedRepos.isNotEmpty) RepoSection(kind: SectionKind.pinned, repos: pinnedRepos),
      for (final f in folders)
        if (!searching || byFolder[f.id]!.isNotEmpty)
          RepoSection(
            kind: SectionKind.folder,
            folder: f,
            repos: byFolder[f.id]!,
            collapsed: f.collapsed && !searching,
          ),
      if (other.isNotEmpty || (folders.isEmpty && pinnedRepos.isEmpty && archivedRepos.isEmpty))
        RepoSection(kind: SectionKind.other, repos: other),
      if (archivedRepos.isNotEmpty)
        RepoSection(kind: SectionKind.archived, repos: archivedRepos, collapsed: archivedCollapsed && !searching),
    ];
  }

  static bool matches(GhRepo r, String query) =>
      r.fullName.toLowerCase().contains(query) || (r.description?.toLowerCase().contains(query) ?? false);

  Map<String, dynamic> toJson() => {
    'folders': [for (final f in folders) f.toJson()],
    'folderOf': folderOf,
    'archived': archived.toList(),
    'unarchived': unarchived.toList(),
    'hidden': hidden.toList(),
    'hiddenOwners': hiddenOwners.toList(),
    'sources': sources.toJson(),
    'sort': sort.name,
    'archivedCollapsed': archivedCollapsed,
  };
}

enum SectionKind { pinned, folder, other, archived }

class RepoSection {
  const RepoSection({required this.kind, required this.repos, this.folder, this.collapsed = false});

  final SectionKind kind;
  final List<GhRepo> repos;

  /// Set for [SectionKind.folder].
  final RepoFolder? folder;
  final bool collapsed;
}

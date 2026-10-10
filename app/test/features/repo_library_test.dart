import 'dart:convert';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:git_reviewer/data/github/models/models.dart';
import 'package:git_reviewer/features/repos/repo_library.dart';

GhRepo _r(String fullName, {int daysAgo = 0, bool archived = false, String? description}) {
  final [owner, name] = fullName.split('/');
  return GhRepo(
    owner: owner,
    name: name,
    defaultBranch: 'main',
    isPrivate: false,
    description: description,
    pushedAt: DateTime(2026, 10, 10).subtract(Duration(days: daysAgo)),
    archived: archived,
  );
}

final _repos = [
  _r('me/app', daysAgo: 1),
  _r('me/blog', daysAgo: 30),
  _r('acme/api', daysAgo: 2, description: 'Payments backend'),
  _r('acme/web', daysAgo: 3),
  _r('acme/legacy', daysAgo: 400, archived: true),
  _r('Spam/thing', daysAgo: 0),
];

/// `kind folder: repo, repo (collapsed)` per section.
List<String> _shape(List<RepoSection> sections) => [
  for (final s in sections)
    '${s.kind.name}${s.folder == null ? '' : ' ${s.folder!.name}'}: ${s.repos.map((r) => r.fullName).join(', ')}'
        '${s.collapsed ? ' (collapsed)' : ''}',
];

void main() {
  const work = RepoFolder(id: 'w', name: 'Work', color: Color(0xFF4493F8));
  const side = RepoFolder(id: 's', name: 'Side', color: Color(0xFF3FB950));

  test('no organizing: one section, newest push first, without the hidden', () {
    final lib = const RepoLibrary().setOwnerHidden('spam', hide: true);
    expect(_shape(lib.arrange(_repos)), [
      'other: me/app, acme/api, acme/web, me/blog',
      'archived: acme/legacy (collapsed)',
    ]);
  });

  test('pinned first, then folders in order, Other, and Archived (collapsed)', () {
    final lib = const RepoLibrary()
        .withFolder(work)
        .withFolder(side)
        .move(['ACME/api', 'acme/web'], 'w')
        .move(['me/blog'], 's')
        .setArchived(['me/app'], archive: true)
        .setHidden(['spam/thing'], hide: true);
    expect(_shape(lib.arrange(_repos, pinned: {'acme/web'})), [
      'pinned: acme/web',
      'folder Work: acme/api',
      'folder Side: me/blog',
      'archived: me/app, acme/legacy (collapsed)',
    ]);
    expect(lib.folderFor('Acme/API')?.name, 'Work', reason: 'GitHub names ignore case');
  });

  test('searching opens collapsed sections, drops empty folders, and matches descriptions', () {
    final lib = const RepoLibrary().withFolder(work.copyWith(collapsed: true)).withFolder(side).move(['acme/api'], 'w');
    expect(_shape(lib.arrange(_repos, query: 'payments')), ['folder Work: acme/api']);
    expect(_shape(lib.arrange(_repos, query: 'legacy')), ['archived: acme/legacy']);
    expect(
      lib.arrange(_repos).where((s) => s.folder?.name == 'Side').single.repos,
      isEmpty,
      reason: 'shown, to drop into',
    );
  });

  test('sort by name', () {
    final lib = const RepoLibrary(sort: RepoSort.name);
    expect(lib.arrange(_repos).first.repos.map((r) => r.fullName), [
      'acme/api',
      'acme/web',
      'me/app',
      'me/blog',
      'Spam/thing',
    ]);
  });

  test('filing a repo unarchives it; deleting a folder sends its repos to Other', () {
    var lib = const RepoLibrary().withFolder(work).setArchived(['me/app'], archive: true).move(['me/app'], 'w');
    expect(lib.archived, isEmpty);
    expect(lib.folderOf, {'me/app': 'w'});
    lib = lib.withoutFolder('w');
    expect(lib.folders, isEmpty);
    expect(lib.folderOf, isEmpty);
    expect(lib.move(['me/app'], 'w').folderOf, {'me/app': 'w'});
    expect(const RepoLibrary().move(['me/app'], 'w').move(['me/app'], null).folderOf, isEmpty);
  });

  test('folders reorder, rename and collapse', () {
    const third = RepoFolder(id: 't', name: 'Third', color: Color(0xFFDB61A2));
    var lib = const RepoLibrary().withFolder(work).withFolder(side).withFolder(third);
    expect(lib.reorderFolder(2, 0).folders.map((f) => f.id), ['t', 'w', 's']);
    expect(lib.reorderFolder(0, 2).folders.map((f) => f.id), ['s', 't', 'w']);
    lib = lib.withFolder(work.copyWith(name: 'Job')).toggleCollapsed('s');
    expect(lib.folders.map((f) => (f.name, f.collapsed)), [('Job', false), ('Side', true), ('Third', false)]);
  });

  test('what to load maps onto GitHub\'s affiliation filter', () {
    expect(const RepoSources().affiliation, 'owner,collaborator,organization_member');
    expect(const RepoSources(organizations: false).affiliation, 'owner,collaborator');
    expect(const RepoSources(owned: false, collaborations: false, organizations: false).affiliation, '');
  });

  test('round-trips through JSON; junk and dangling folders are dropped', () {
    final lib =
        const RepoLibrary(sort: RepoSort.name, archivedCollapsed: false, sources: RepoSources(collaborations: false))
            .withFolder(work)
            .move(['me/app'], 'w')
            .setArchived(['me/blog'], archive: true)
            .setHidden(['spam/thing'], hide: true)
            .setOwnerHidden('Spam', hide: true);
    final back = RepoLibrary.parse(jsonEncode(lib.toJson()));
    expect(back.folders.single.name, 'Work');
    expect(back.folders.single.color, work.color);
    expect(back.folderOf, lib.folderOf);
    expect(back.archived, {'me/blog'});
    expect(back.hidden, {'spam/thing'});
    expect(back.hiddenOwners, {'spam'});
    expect(
      (back.sort, back.archivedCollapsed, back.sources.affiliation),
      (RepoSort.name, false, 'owner,organization_member'),
    );

    final junk = RepoLibrary.fromJson({
      'folders': [42, work.toJson()],
      'folderOf': {'me/app': 'gone', 'me/blog': 'w', 'x/y': 3},
      'hidden': ['a/b', 7],
      'sort': 'nope',
    });
    expect(junk.folderOf, {'me/blog': 'w'});
    expect(junk.hidden, {'a/b'});
    expect(junk.sort, RepoSort.pushed);
    expect(RepoLibrary.parse('not json').folders, isEmpty);
  });
}

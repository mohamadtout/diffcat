import 'github_client.dart';
import 'github_exception.dart';
import 'models/models.dart';

/// Typed GitHub REST endpoints used by the app.
///
/// Everything here is read straight from GitHub — nothing is cloned to the
/// device. See docs/architecture.md for the git-command → endpoint mapping.
class GitHubApi {
  GitHubApi(this.client);

  final GitHubClient client;

  String _r(RepoRef r) => '/repos/${r.owner}/${r.name}';

  Future<GhUser> viewer() async => GhUser.fromJson(await client.getJson('/user') as Map<String, dynamic>);

  Future<GhPage<GhRepo>> myRepos({int page = 1}) => client.getPage(
    '/user/repos',
    query: {'sort': 'pushed', 'per_page': 50, 'page': page, 'affiliation': 'owner,collaborator,organization_member'},
    parse: GhRepo.fromJson,
  );

  Future<GhRepo> repo(RepoRef r) async => GhRepo.fromJson(await client.getJson(_r(r)) as Map<String, dynamic>);

  Future<List<GhBranch>> branches(RepoRef r) =>
      client.getAll('${_r(r)}/branches', parse: GhBranch.fromJson, maxPages: 5);

  Future<List<GhBranch>> tags(RepoRef r) => client.getAll('${_r(r)}/tags', parse: GhBranch.fromJson, maxPages: 2);

  /// `git log [ref] [-- path]`. Passing [path] gives the file's history.
  Future<GhPage<GhCommit>> commits(RepoRef r, {String? ref, String? path, int page = 1, int perPage = 30}) =>
      client.getPage(
        '${_r(r)}/commits',
        query: {'sha': ?ref, 'path': ?path, 'page': page, 'per_page': perPage},
        parse: GhCommit.fromJson,
      );

  /// How many commits [ref] has (`git rev-list --count`): one request, using
  /// the page count of a one-per-page listing.
  Future<int> commitCount(RepoRef r, String ref) async {
    final p = await commits(r, ref: ref, perPage: 1);
    return p.lastPage ?? p.items.length;
  }

  /// `git show <sha>` including every changed file (GitHub caps at 3000).
  ///
  /// Unpaginated, GitHub returns up to 300 files. Beyond that the file list
  /// must be paged (max 100 per page, 3000 total), so re-fetch it that way.
  Future<GhCommit> commit(RepoRef r, String sha) async {
    final first = GhCommit.fromJson(await client.getJson('${_r(r)}/commits/$sha') as Map<String, dynamic>);
    if (first.files.length < 300) return first;
    const perPage = 100;
    final files = <GhFileChange>[];
    for (var page = 1; page <= 30; page++) {
      final next = GhCommit.fromJson(
        await client.getJson('${_r(r)}/commits/$sha', query: {'per_page': perPage, 'page': page})
            as Map<String, dynamic>,
      );
      files.addAll(next.files);
      if (next.files.length < perPage) break;
    }
    return first.copyWith(files: files);
  }

  /// `git diff base...head`.
  Future<GhCompare> compare(RepoRef r, String base, String head) async => GhCompare.fromJson(
    await client.getJson('${_r(r)}/compare/${Uri.encodeComponent(base)}...${Uri.encodeComponent(head)}')
        as Map<String, dynamic>,
  );

  /// Full recursive tree for a ref (branch, tag or sha).
  Future<GhTree> tree(RepoRef r, String ref) async => GhTree.fromJson(
    await client.getJson('${_r(r)}/git/trees/${Uri.encodeComponent(ref)}', query: {'recursive': '1'})
        as Map<String, dynamic>,
  );

  /// `git show ref:path`.
  Future<String> fileContent(RepoRef r, String path, String ref) =>
      client.getRaw(contentsPath(r, path), query: {'ref': ref});

  /// Request path of a file's contents (offline downloads file text under it).
  static String contentsPath(RepoRef r, String path) =>
      '/repos/${r.owner}/${r.name}/contents/${path.split('/').map(Uri.encodeComponent).join('/')}';

  /// The whole tree at [ref] as a .tar.gz (one request instead of one per file).
  Future<List<int>> tarball(RepoRef r, String ref) => client.getBytes('${_r(r)}/tarball/${Uri.encodeComponent(ref)}');

  /// `git blame` at [ref]. GraphQL only (there's no REST blame), and GraphQL
  /// always needs a token.
  Future<List<BlameRange>> blame(RepoRef r, String path, String ref) async {
    const query = r'''
query($owner: String!, $name: String!, $ref: String!, $path: String!) {
  repository(owner: $owner, name: $name) {
    object(expression: $ref) {
      ... on Commit {
        blame(path: $path) {
          ranges {
            startingLine endingLine age
            commit { oid messageHeadline committedDate author { name user { login } } }
          }
        }
      }
    }
  }
}''';
    final data = await graphql(query, {'owner': r.owner, 'name': r.name, 'ref': ref, 'path': path});
    final object = (data['repository'] as Map<String, dynamic>?)?['object'] as Map<String, dynamic>?;
    final blame = object?['blame'] as Map<String, dynamic>?;
    if (blame == null) throw GitHubException('No blame for $path at $ref', statusCode: 404);
    return [for (final r in blame['ranges'] as List<dynamic>) BlameRange.fromJson(r as Map<String, dynamic>)];
  }

  /// Runs a GraphQL query. GraphQL reports failures as `errors` in a 200
  /// response; those become [GitHubException]s like REST failures.
  Future<Map<String, dynamic>> graphql(String query, Map<String, dynamic> variables) async {
    final res = await client.postJson('/graphql', {'query': query, 'variables': variables}) as Map<String, dynamic>;
    final errors = res['errors'] as List<dynamic>?;
    if (errors != null && errors.isNotEmpty) {
      final first = errors.first as Map<String, dynamic>;
      throw GitHubException(
        (first['message'] as String?) ?? 'GitHub GraphQL request failed',
        statusCode: first['type'] == 'NOT_FOUND' ? 404 : null,
      );
    }
    return (res['data'] as Map<String, dynamic>?) ?? const {};
  }

  /// Open pull requests across GitHub matching search [qualifiers]
  /// (`review-requested:@me`…), most recently updated first. Needs a token
  /// for `@me`.
  Future<GhSearchResult<GhSearchPull>> searchPulls(String qualifiers, {int perPage = 50}) async {
    final j = await client.getJson(
      '/search/issues',
      query: {'q': 'is:pr is:open archived:false $qualifiers', 'sort': 'updated', 'order': 'desc', 'per_page': perPage},
    ) as Map<String, dynamic>;
    return GhSearchResult([
      for (final i in j['items'] as List<dynamic>) GhSearchPull.fromJson(i as Map<String, dynamic>),
    ], total: (j['total_count'] as int?) ?? 0);
  }

  Future<GhPage<GhPull>> pulls(RepoRef r, {String state = 'open', int page = 1}) => client.getPage(
    '${_r(r)}/pulls',
    query: {'state': state, 'page': page, 'per_page': 30, 'sort': 'updated', 'direction': 'desc'},
    parse: GhPull.fromJson,
  );

  Future<GhPull> pull(RepoRef r, int number) async =>
      GhPull.fromJson(await client.getJson('${_r(r)}/pulls/$number') as Map<String, dynamic>);

  Future<List<GhFileChange>> pullFiles(RepoRef r, int number) =>
      client.getAll('${_r(r)}/pulls/$number/files', parse: GhFileChange.fromJson, maxPages: 30);

  /// Line comments of a pull request, oldest first.
  Future<List<GhReviewComment>> reviewComments(RepoRef r, int number) =>
      client.getAll('${_r(r)}/pulls/$number/comments', parse: GhReviewComment.fromJson, maxPages: 10);

  /// Submitted reviews (approve / request changes / comment), oldest first.
  Future<List<GhReview>> reviews(RepoRef r, int number) =>
      client.getAll('${_r(r)}/pulls/$number/reviews', parse: GhReview.fromJson, maxPages: 5);

  /// Submits a review with its line [comments] in one go, against [commitId]
  /// (the head the comments were written on).
  Future<void> submitReview(
    RepoRef r,
    int number, {
    required String commitId,
    required ReviewEvent event,
    String body = '',
    List<Map<String, dynamic>> comments = const [],
  }) => client.postJson('${_r(r)}/pulls/$number/reviews', {
    'commit_id': commitId,
    'event': event.api,
    if (body.isNotEmpty) 'body': body,
    if (comments.isNotEmpty) 'comments': comments,
  });

  /// One line comment outside a review ("Add single comment").
  Future<void> addReviewComment(
    RepoRef r,
    int number, {
    required String commitId,
    required String path,
    required int line,
    required DiffSide side,
    required String body,
  }) => client.postJson('${_r(r)}/pulls/$number/comments', {
    'commit_id': commitId,
    'path': path,
    'line': line,
    'side': side.api,
    'body': body,
  });

  Future<void> replyToReviewComment(RepoRef r, int number, int commentId, String body) =>
      client.postJson('${_r(r)}/pulls/$number/comments/$commentId/replies', {'body': body});

  Future<List<GhCommit>> pullCommits(RepoRef r, int number) =>
      client.getAll('${_r(r)}/pulls/$number/commits', parse: GhCommit.fromJson, maxPages: 3);
}

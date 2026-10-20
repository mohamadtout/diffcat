import 'actions.dart';

/// One check on a commit (`GET /repos/{o}/{r}/commits/{ref}/check-runs`):
/// an Actions job, or another app's check.
class GhCheckRun {
  const GhCheckRun({required this.id, required this.name, required this.state, this.htmlUrl});

  factory GhCheckRun.fromJson(Map<String, dynamic> j) => GhCheckRun(
    id: j['id'] as int,
    name: (j['name'] as String?) ?? '',
    state: RunState.from(j['status'] as String?, j['conclusion'] as String?),
    htmlUrl: j['html_url'] as String?,
  );

  final int id;
  final String name;
  final RunState state;
  final String? htmlUrl;
}

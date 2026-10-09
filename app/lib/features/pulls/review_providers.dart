import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/storage.dart';
import '../../data/github/models/models.dart';
import '../auth/auth_controller.dart';
import 'pulls_providers.dart';
import 'review.dart';

final reviewCommentsProvider = FutureProvider.autoDispose.family<List<GhReviewComment>, PullKey>(
  (ref, k) => ref.watch(githubApiProvider).reviewComments(k.repo, k.number),
);

final reviewsProvider = FutureProvider.autoDispose.family<List<GhReview>, PullKey>(
  (ref, k) => ref.watch(githubApiProvider).reviews(k.repo, k.number),
);

/// The review being written on a pull request, persisted per PR.
final reviewDraftProvider = NotifierProvider.family<ReviewDraftNotifier, ReviewDraft, PullKey>(ReviewDraftNotifier.new);

class ReviewDraftNotifier extends Notifier<ReviewDraft> {
  ReviewDraftNotifier(this.key);
  final PullKey key;

  String get _prefsKey => StoreKeys.reviewDraft(key.repo.fullName, key.number);

  @override
  ReviewDraft build() {
    final raw = ref.watch(sharedPrefsProvider).getString(_prefsKey);
    if (raw == null) return const ReviewDraft();
    try {
      return ReviewDraft.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on Object {
      return const ReviewDraft();
    }
  }

  void _save(ReviewDraft d) {
    state = d;
    final prefs = ref.read(sharedPrefsProvider);
    d.isEmpty ? prefs.remove(_prefsKey) : prefs.setString(_prefsKey, jsonEncode(d.toJson()));
  }

  /// Adds a comment written against [headSha]. The first comment pins the
  /// draft to that head: line numbers are relative to it.
  void add(DraftComment c, {required String headSha}) =>
      _save(state.copyWith(headSha: state.headSha ?? headSha, comments: [...state.comments, c]));

  void replace(DraftComment old, DraftComment next) =>
      _save(state.copyWith(comments: [for (final c in state.comments) identical(c, old) ? next : c]));

  void remove(DraftComment c) => _save(state.copyWith(comments: [...state.comments]..remove(c)));

  void setBody(String body) => _save(state.copyWith(body: body));

  void discard() => _save(const ReviewDraft());

  /// Submits the draft as one review, then forgets it. Throws (keeping the
  /// draft) if GitHub refuses.
  Future<void> submit(ReviewEvent event, {required String headSha}) async {
    final d = state;
    await ref
        .read(githubApiProvider)
        .submitReview(
          key.repo,
          key.number,
          commitId: d.headSha ?? headSha,
          event: event,
          body: d.body.trim(),
          comments: d.apiComments(),
        );
    _save(const ReviewDraft());
    ref
      ..invalidate(reviewCommentsProvider(key))
      ..invalidate(reviewsProvider(key));
  }
}

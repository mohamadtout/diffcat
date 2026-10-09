import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/github/models/models.dart';
import '../auth/auth_controller.dart';

/// The inbox's lists, each a GitHub search for open pull requests.
enum InboxSection {
  reviewRequested('Review requested', 'review-requested:@me', Icons.rate_review_outlined),
  mine('Yours', 'author:@me', Icons.person_outline),
  mentioned('Mentioned', 'mentions:@me', Icons.alternate_email),
  assigned('Assigned', 'assignee:@me', Icons.assignment_ind_outlined);

  const InboxSection(this.label, this.qualifiers, this.icon);
  final String label;
  final String qualifiers;
  final IconData icon;
}

final inboxProvider = FutureProvider.autoDispose.family<GhSearchResult<GhSearchPull>, InboxSection>(
  (ref, s) => ref.watch(githubApiProvider).searchPulls(s.qualifiers),
);

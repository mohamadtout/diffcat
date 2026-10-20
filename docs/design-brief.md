# Diffcat — design brief

## What it is
Diffcat: Code Review for Git. A mobile app (Flutter, Android first, iOS/iPadOS planned) for reviewing GitHub code
changes from a phone: repos, commits, diffs, pull requests, CI/Actions, notifications, offline copies, and an SSH
terminal to the user's own machine. No backend.

## Users and context
Developers and reviewers away from their desk: on a train, in bed, in a queue. One hand, short sessions, often
at night. They are triaging ("is this safe to merge?"), not writing code. Reading diffs on a small screen is the
core job; everything else supports it.

## Brand
- Name: "Diffcat". Mascot: our own cat drawing (app/assets/icon/), never the Octocat. Never use "GitHub" in the
  name or icon.
- Seed color: #2F81F7 (blue), via Material 3 `ColorScheme.fromSeed` in app/lib/core/theme/app_theme.dart.
- Tone: calm, precise, a bit friendly. A developer tool, not a toy and not a corporate dashboard.
- Diff colors are user-editable (Settings → Code view); any redesign must keep added/removed lines distinguishable
  without relying on color alone.

## Hard constraints (do not propose changes that break these)
- Responsive: phone, foldable, tablet (split view), desktop. Use WindowSize / SplitView / ReadableWidth.
- Flutter + Material 3. No new heavy dependencies; no web-only ideas (CSS, hover-only affordances).
- Works at text scale up to 2x and at 320 px wide. Touch targets >= 48 dp.
- Light and dark must both be first-class.
- Every screen is reachable by a route in `Routes`.
- Store screenshots and docs use demo data only (test/support/demo_github.dart).

## What I want from a review
Hierarchy, density, spacing rhythm, typography, color use, navigation clarity, empty/loading/error states, diff
readability, one-handed reach, tablet layout. Concrete and ranked by impact, not a generic style rewrite.

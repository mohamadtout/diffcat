# core/markdown

GitHub-flavoured Markdown for pull request descriptions and review comments, written for Diffcat and kept
publishable as a pub package (owner decision, docs/decisions.md D22).

- `markdown.dart`: the parser. Pure Dart, no imports. Blocks and inlines as sealed classes.
- `github_refs.dart`: `#123`, `owner/repo#123`, `@user` and commit SHAs as github.com links. Pure Dart.
- `markdown_view.dart`: the Flutter renderer (Material theme, one `SelectionArea`, links and code highlighting
  through callbacks). Imports only Flutter.

Keep it that way: nothing in this folder may import the app. App behaviour (in-app routes for links, the syntax
highlighter, the code font) is passed in, see `features/pulls/pull_markdown.dart`. Tests:
`test/core/markdown_test.dart` (parser, references) and `test/widgets/markdown_view_test.dart` (renderer).

To publish: move the folder to `packages/<name>/lib/`, add a pubspec (Flutter SDK only), move the tests, and
depend on it by path from `app/pubspec.yaml`.

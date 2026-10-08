# Commands & buttons

There are two places to run commands. They're deliberately separate:

| | API console (repo → Console tab) | SSH terminal (Terminal tab) |
|---|---|---|
| Runs on | GitHub's API | Your own machine via SSH |
| Needs | Only the GitHub token | An SSH host you control |
| Clone needed | No | The repo lives on that machine, not the phone |
| Good for | Quick history/diff/file queries | lazygit, arbitrary git, writes (commit, rebase, push) |

## API console reference

The `git ` prefix is optional. `HEAD` means the branch selected in the repo screen.

| Command | Does |
|---|---|
| `help` | List commands |
| `log [ref] [-n N] [-- path]` | History (`-N` and `--max-count=N` also work; max 100) |
| `history <path> [-n N]` | Commits that touched a file |
| `show <sha> [--patch\|--stat\|--name-only]` | Commit header, message, files (name-status by default) |
| `diff <a>..<b>` / `<a>...<b>` / `<a> <b>` | Compare; same output flags as `show` |
| `since <ref> [head]` | Files changed since a commit/tag (alias `changed-since`) |
| `ls [dir] [--ref R]` | Directory listing |
| `cat <path> [--ref R]` | File contents (first 400 lines; tap to open the viewer) |
| `branches`, `tags` | List refs (tap a branch to switch to it) |
| `prs [--state open\|closed\|all]` | Pull requests |
| `pr <n>` | PR summary and files |
| `open <sha\|#pr\|path>` | Jump to the visual viewer |
| `rate` | Remaining API quota |
| `clear` | Clear scrollback |

Ref syntax: branch, tag, SHA, `HEAD`, `HEAD~N` / `<ref>~N` (N ≤ 99, follows GitHub's listing order, which is exact for linear history), and `@latest-tag` (the first tag GitHub lists).

Output lines with a SHA, file or PR can be tapped to open them, and long-pressed to copy.

**To add a command:** add a case in `CommandExecutor.run`, a line in `helpText`, a test in `test/features/command_executor_test.dart`, and a row in the table above.

## SSH key notation

Custom SSH buttons and a host's startup command are typed into the shell. Special keys use `<…>` tokens (case-insensitive):

| Token | Key |
|---|---|
| `<enter>` `<cr>` | Enter |
| `<esc>` `<tab>` `<s-tab>` `<bs>` `<del>` `<space>` | as named |
| `<up>` `<down>` `<left>` `<right>` `<home>` `<end>` `<pgup>` `<pgdn>` | navigation |
| `<f1>` … `<f12>` | function keys |
| `<c-x>` | Ctrl+x (e.g. `<c-c>` to interrupt) |
| `<a-x>` | Alt+x |
| `<lt>` | a literal `<` |

Unknown tokens are sent literally, so `a > b` and `<foo>` are safe. Examples:

```
cd ~/code/app && lazygit<enter>      # startup command
git fetch --all --prune<enter>       # button
<esc>:wq<enter>                      # leave vim
P                                    # lazygit: push (when lazygit is focused)
```

## Default buttons

Seeded on first launch. Edit them in **Settings → Command buttons** (or via the "Edit" chip). **Reset to defaults** restores them.

- API: `Last 20`, `Open PRs`, `Branches`, `Since last tag`
- SSH: `lazygit`, `status`, `fetch`, `graph`, `^C`
- lazygit macros (single keys, used inside lazygit): `LG stage all` (a), `LG commit` (c), `LG pull` (p), `LG push` (P), `LG quit` (q)

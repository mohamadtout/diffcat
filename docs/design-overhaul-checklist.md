# Design overhaul: checks to do on a device

The `feature/design-overhaul` branch implements [design-review.md](design-review.md). Everything here passed
`make check` and was looked at in `make design-shots` screenshots, but these need a real phone or tablet (or
someone's eyes and hands). Tick them off before merging.

Run `make run DEVICE=<id>` on a phone and a tablet, in light and dark, and once with the system font size at its
largest.

## 1. Colors (brand scheme, status colors, diff bars)

- [ ] The blue looks like the brand (#2F81F7 family) on a real screen, in light and dark, and isn't too loud on
      switches, the FAB and selected chips.
- [ ] Dark mode at night brightness: added and removed diff lines are easy to tell apart from unchanged ones (OLED
      and LCD if you have both).
- [ ] The 3 dp bar at the left of changed lines lines up with the row, also with wrapped lines and while panning a
      long line sideways.
- [ ] Your own diff color profiles (if you had any) look as before; only the default "GitHub" preset changed.
- [ ] Text fields: every form still looks right with the outlined style (host editor, dialogs, sheets, search
      fields), and nothing has a double border.

## 2. Empty and error states, the cat

- [ ] The cat looks sharp (not blurry or jagged) and calm in light and dark: signed-out home, Inbox "All clear",
      Downloads "Nothing downloaded yet", signed-out Inbox. It should feel friendly, not like an ad.
- [ ] In landscape on a phone the cat hides and the message and button stay visible.
- [ ] Rate limit: signed out, use up the 60 requests (or wait for a real limit) and check the message shows the right
      reset time in your time zone and "Sign in for 5,000 an hour" opens sign-in.
- [ ] "Show closed" on a repo with no open PRs switches the filter; "Browse repos" goes to the repo list; "Back to
      hosts" after deleting a host from another screen.

## 3. Host-key dialog

- [ ] Connect to a host whose key changed (or edit the saved fingerprint): the dialog reads well, Cancel is the
      highlighted button, and the fingerprints are selectable and easy to compare with `ssh-keygen -lf` output.
- [ ] `make ssh-test` still passes (it trusts a first connection with the "Trust" button).

## 4. Phone chrome

- [ ] Repo screen on a phone: the row under the top bar (branch, owner, bell) feels like part of the bar, the branch
      picker is easy to hit with a thumb, and the menu's "Notify me of commits & PRs" toggles watching (and the bell
      appears in the row).
- [ ] Repo rows with pin, bell and Offline chip still read well; the Offline chip is tappable.
- [ ] PR tabs scroll sideways smoothly at the largest font size; swipe between tabs still works.
- [ ] Review sheet: the radio list feels natural with one hand; Submit review stays reachable with the keyboard open.
- [ ] Download sheet at the largest font: options scroll, Download/Update stays at the bottom, also with the keyboard
      open (typing the number of commits).
- [ ] Downloads → a repo: the menu's Update and Delete work (Delete asks first).

## 5. Diff first

- [ ] A commit with a long message: the body shows two lines and More/Less works; the text stays selectable when
      open. The header scrolls away with the diff and the sticky file bar still pins.
- [ ] Set the system font to its largest: code and line numbers grow a little (1.15×) while the header, toolbars and
      the rest of the app grow fully. Decide if 1.15 is the right cap.
- [ ] The chip row under a commit (parents, Changed since this, Browse at this commit) scrolls sideways when it
      doesn't fit, and each chip opens the right screen.
- [ ] Blame on a phone: "2d LK" style labels are clear enough; tapping one still opens the commit. On a tablet the
      login is shown as before.
- [ ] PR header: a very long title folds to two lines; the Overview tab shows it in full.

## 6. Merge readiness

- [ ] On a real repo, open PRs in each state and check the line under the title matches what github.com shows:
      ready, failing checks, running checks (it doesn't refresh by itself yet: pull to refresh or reopen), conflicts
      (`mergeable_state: dirty`), changes requested, required reviews missing (`blocked`), draft.
- [ ] GitHub sometimes answers `mergeable_state: unknown` right after a push: the line says "Checking…"; reopening
      later should resolve it.
- [ ] Repos with many checks (more than 100) or with only commit statuses (old CI integrations, not check runs): the
      card may undercount. Decide whether to also read `GET …/commits/{sha}/status`.
- [ ] Offline (downloaded PR, offline mode): the line says "Checks unavailable", nothing errors.
- [ ] Rate limit: each open PR costs one more request (check runs); fine signed in, worth noticing signed out.

## 7. Markdown

- [ ] Open real PRs with rich descriptions (templates with checklists, tables, code blocks, images, `<details>`) and
      compare with github.com. Note anything that renders worse than plain text did.
- [ ] Links: a PR or commit link opens in the app; an issue link, `@user` and external links open the browser;
      relative links (`docs/x.md`) open the file on github.com.
- [ ] Selecting text across paragraphs, lists and code works with one long-press and drag; links still open with a
      tap.
- [ ] Long code lines in a fenced block scroll sideways inside the block, not the whole page.
- [ ] Review comments in the diff are formatted too and keep the full system font size.

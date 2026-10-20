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

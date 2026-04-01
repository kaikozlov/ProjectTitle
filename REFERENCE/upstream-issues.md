# Upstream Issue Backlog

Working list of upstream-origin issues and requests we may still address in this fork.

Last audited: 2026-03-31 on `sane`, cross-checked against the current code and selected upstream issue bodies/logs.

This file is intentionally de-noised:

- Excludes issues already fixed in our fork
- Excludes duplicates, translations, documentation-only items, and installer confusion
- Excludes ideas we are not currently planning to pursue

---

## Recently Completed

| Issue # | Title | Notes |
| ----- | ----- | ----- |
| 18 | Skip hidden files during auto-scan/indexing | Done. Hidden files now follow the same `show_hidden` rule as hidden directories, while macOS `._*` files remain excluded. |
| 142 | Add a menu toggle to disable progress bars | Done. Added `Hide progress bars` under Advanced settings -> Book display, wired to `force_no_progressbars`. |

---

## Planned Backlog

Ordered from easiest to hardest.


| Order | Issue #  | Title                                                     | Difficulty   | Why It Still Matters                                                                                                                                                                          | Main Code Area                                                  |
| ----- | -------- | --------------------------------------------------------- | ------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------- |
| 1     | 148      | Normalize tag/keyword separators across file types        | Small        | `formatTags()` assumes newline-separated keywords, but upstream reports and current code indicate some formats store tags differently.                                                        | `ptutil.lua`, `bookinfomanager.lua`                             |
| 2     | 28       | Swap author/series display order                          | Small        | Frequently requested and localized to one formatting path plus one setting.                                                                                                                   | `ptutil.lua`, `main.lua`                                        |
| 3     | 130      | Make the back arrow long-press only                       | Small        | Niche but straightforward: current title bar wiring always navigates up on tap.                                                                                                               | `covermenu.lua`, `main.lua`                                     |
| 4     | 143      | Center pagination controls in the footer                  | Small        | Pure layout option; low risk and easy to scope.                                                                                                                                               | `covermenu.lua`                                                 |
| 5     | 70 / 132 | Add per-item footer device-info toggles                   | Small-Medium | Footer device info is currently all-or-nothing. Users want selective control over clock, wifi, battery, frontlight, and warmth.                                                               | `ptutil.lua`, `main.lua`                                        |
| 6     | 146 / 79 | Font hardening for desktop/macOS/AppImage/Flatpak crashes | Medium       | Highest user-impact unresolved bug. `ptutil.getFontFace()` can still return `nil`, and `mosaicmenu.lua` still has raw `Font:getFace()` calls. Treat these reports as one font-failure bucket. | `ptutil.lua`, `mosaicmenu.lua`, `resources/2-font-override.lua` |
| 7     | 165      | Show image previews in PathChooser / file chooser mode    | Medium       | Still open upstream and clearly missing in our code. Important for wallpaper/image-picking workflows.                                                                                         | `listmenu.lua`, `mosaicmenu.lua`, `covermenu.lua`               |
| 8     | 91       | Filter library mode by read status                        | Medium       | Useful feature, but needs actual filter UI and state handling rather than a simple formatting tweak.                                                                                          | `covermenu.lua`, library mode item-building paths               |
| 9     | 137      | Refresh footer device info live                           | Medium       | Useful, but trickier than it sounds because periodic refreshes need to be gentle on e-ink and KOReader’s redraw model.                                                                        | `covermenu.lua`, `ptutil.lua`                                   |


---

## Per-Issue Notes

### `#148` Tags / Keywords Separator

- Current status: unfixed
- Why: `ptutil.formatTags()` assumes `\n` separators, but upstream reports show PDFs and other formats may store keywords differently.
- Practical fix: normalize at insert time, or make `formatTags()` split on multiple delimiters.

### `#28` Author / Series Order

- Current status: unfixed
- Why: `formatAuthorSeries()` always emits authors before series.
- Practical fix: add a setting and branch the formatter.

### `#130` Long-Press Back Arrow

- Current status: unfixed
- Why: `right2_icon_tap_callback` goes up immediately; there is no optional long-press-only mode.
- Practical fix: add one setting and adjust title bar callback wiring.

### `#143` Centered Pagination Controls

- Current status: unfixed
- Why: footer layout only supports left or right placement via `reverse_footer`.
- Practical fix: add a centered footer mode.

### `#70 / #132` Footer Device-Info Toggles

- Current status: unfixed
- Why: footer device info is currently driven by a hardcoded config block in `ptutil.formatFooterText()`.
- Practical fix: add settings for individual footer items and expose them in the menu.

### `#146 / #79` Font Hardening Bucket

- Current status: unfixed and higher risk than it first looked
- Why:
  - `ptutil.getFontFace()` can still return `nil` after exhausting fallbacks
  - `mosaicmenu.lua` still contains 5 direct `Font:getFace()` calls
  - the bundled `resources/2-font-override.lua` patch increases the blast radius when Source fonts fail to load
- Practical fix:
  - make `ptutil.getFontFace()` truly non-nil
  - replace the remaining raw `Font:getFace()` calls in `mosaicmenu.lua`

### `#165` PathChooser Image Previews

- Current status: unfixed
- Why: PathChooser rendering still deliberately falls back to text labels instead of image previews.
- Practical fix: teach the pathchooser branches in list/grid rendering to display image thumbnails when the selected files are images.

### `#91` Library Filter By Read Status

- Current status: unfixed
- Why: current library mode can sort opened books higher, but it does not expose filtering by status.
- Practical fix: add filter UI and apply it in the library item-generation path.

### `#137` Live Footer Refresh

- Current status: unfixed
- Why: footer text updates on page changes, not on a timer, so clock/battery/wifi can go stale.
- Practical fix: add a lightweight scheduled refresh loop with redraw limits.

---

## Key Files

- `bookinfomanager.lua`: hidden-file filtering, metadata ingestion
- `main.lua`: settings and menu toggles
- `ptutil.lua`: font fallback, tag formatting, footer formatting, author/series formatting
- `covermenu.lua`: footer layout, title bar callbacks, library mode wiring
- `mosaicmenu.lua`: remaining raw `Font:getFace()` calls, PathChooser rendering
- `listmenu.lua`: PathChooser rendering
- `resources/2-font-override.lua`: bundled font remapping patch


# AGENTS.md

This file provides guidance to coding agents working in this repository.

## Project Overview

Project: Title is a KOReader plugin (written in Lua) that enhances the file browser interface with a modern, visually-rich UI. It replaces the default Cover Browser plugin by providing multiple display modes for books with metadata-rich views, cover images, and extensive customization options.

**Key concept**: KOReader loads this plugin as `projecttitle`, but core file-manager code still expects a Cover Browser-compatible object at `ui.coverbrowser`. `ProjectTitle:init()` installs that runtime alias; `_meta.lua` no longer carries a deprecated `name` field.

## Architecture

### Plugin Loading and Initialization (main.lua)

The plugin follows a strict initialization sequence:

1. **Compatibility checks** (`main.lua`):
   - Checks if Cover Browser is disabled (required)
   - Verifies fonts are installed in `koreader/fonts/source/`
   - Verifies icons are installed in `koreader/icons/`
   - Uses an explicit `safe_versions` allow-list (currently the three 2026.07 release identifiers)
   - Rejects unlisted older, newer, and nightly builds
   - Can bypass the version gate with `pt-skipversioncheck.txt` file

2. **Settings migration** (`main.lua`):
   - Uses versioned config migrations (`config_version` 1-12)
   - Current version 12 (as of latest update)
   - Version history:
     - v6: Introduced `use_custom_sorts` and `progress_text_format` (replaced `show_pages_read_as_progress`)
     - v7: Introduced `show_mosaic_titles`
     - v8: Introduced `author_series_order`
     - v9: Introduced `folder_up_requires_hold`
     - v10: Introduced `footer_page_controls_alignment`
     - v11: Introduced footer device-info toggles
     - v12: Retired the plugin's legacy Library mode in favor of KOReader's native flat view
   - Migrates settings as new features are added
   - May trigger a KOReader restart if needed

3. **Display-mode wiring** (`main.lua`, `covermenu.lua`):
   - Saves original KOReader methods as locals at module load time
   - Applies rendering methods to owned FileChooser/BookList instances instead of globally replacing shared Menu methods
   - Wraps `PathChooser.init` only while rich display modes are active
   - Restores FileChooser, PathChooser, history, collections, and search hooks when returning to classic mode or stopping the plugin

### Display Modes

The plugin supports 4 display modes:
- `mosaic_image` - 3×3 grid with cover images
- `list_image_meta` - List with covers and metadata (title/authors)
- `list_only_meta` - Metadata only, no covers
- `list_no_meta` - Filenames only

Each mode can be set independently for:
- File manager (`filemanager_display_mode`)
- History (`history_display_mode`)
- Collections (`collection_display_mode`)

Or unified across all three with the `unified_display_mode` setting.

### Core Modules

**bookinfomanager.lua**: SQLite database manager for book metadata and covers
- Schema version: 20201210
- Database location: `DataStorage:getSettingsDir()/PT_bookinfo_cache.sqlite3`
- Stores extracted metadata (title, authors, series, pages, description, keywords)
- Stores compressed cover images using zstd
- Handles cover extraction and caching
- Exposes `BookInfoManager.max_cover_dimen` for patching max extracted cover dimensions
- Maintains a byte-budgeted KOReader `Cache` of clone-safe decompressed covers
- Provides settings storage in `config` table

**covermenu.lua**: Generic menu implementation
- Configures FileChooser and BookList instances with Project: Title rendering methods
- Implements genItemTable() to build file/folder lists
- Implements setupLayout() for title bar with navigation buttons
- Implements updatePageInfo() for footer with page controls and status info
- Builds a per-render `render_context` so hot paths do not repeatedly hit `BookInfoManager:getSetting()`

**listmenu.lua**: List display mode UI implementation
- Defines ListMenuItem widget for rendering individual list items
- Implements _recalculateDimen() for layout calculations
- Implements _updateItemsBuildUI() to construct list view
- Handles cover images, metadata text, progress bars

**mosaicmenu.lua**: Grid display mode UI implementation
- Defines MosaicMenuItem widget for grid items
- Implements FakeCover for books without cover images
- Implements _recalculateDimen() for grid layout
- Implements _updateItemsBuildUI() to construct grid view
- Supports folder cover images and auto-generated thumbnails

**ptutil.lua**: Utilities and configuration
- Contains all default settings in tables:
  - `list_defaults` - List view configuration (font sizes, limits, progress bars)
  - `grid_defaults` - Grid view configuration
  - `footer_defaults` - Footer font sizes
  - `bookstatus_defaults` - Book status screen fonts
- Font definitions using Source Sans 3 and Source Serif 4
- Helper functions: installFonts(), installIcons(), `findCover()`, `getFolderCover()`, `query_cover_paths()`, `getSubfolderCoverImages()`
- Formatting functions: `formatAuthors()`, `formatSeries()`, `formatAuthorSeries()`, `formatTags()`, `formatProgressText()`, `formatFooterText()`
- Contains performance helpers used by the rendering path, including font-size caching and narrowly-scoped widget pooling

**titlebar.lua**: Custom title bar with navigation buttons (up folder, favorites, history, last document)

**altbookstatuswidget.lua**: Alternative book status/screensaver screen with enhanced layout

**ptdbg.lua**: Debug logging utilities with consistent log prefix

### Folder Cover Generation

The plugin can auto-generate folder covers in two ways:

1. **Custom folder image**: Uses explicit `pt_cover_path` when present, otherwise looks for `cover.*` or `folder.*` (jpg/png/webp/gif) in the directory via `ptutil.findCover()`
2. **Thumbnail grid**: Gets bounded, deterministic candidates from `BookInfoManager`, batch-hydrates their metadata/covers, and displays them as:
   - 2×2 grid layout (default)
   - Diagonal stacked layout (if `use_stacked_foldercovers` enabled)

### Mosaic/Grid View Book Display

**Title and Author Overlay** (`show_mosaic_titles`, `mosaicmenu.lua`):
- Displays title and author text above book covers in grid view
- Added in config version 7, enabled by default
- Uses filename as fallback when title is missing or contains only whitespace (including Unicode whitespace like non-breaking spaces)
- Text appears in a centered, framed container above the cover
- Intelligently reserves vertical space (max 40% of item height) while maintaining minimum cover height (60% of item height or 60px minimum)
- If text doesn't fit within constraints, the overlay is dropped entirely to preserve cover visibility

**Progress Bar Text Display** (`progress_text_format`, `mosaicmenu.lua`):
- Controls text shown alongside progress bars below covers (only when `hide_file_info` is true)
- Added in config version 6, replacing the older `show_pages_read_as_progress` setting
- Four display options:
  - `status_only` - Progress bar only, no text
  - `status_and_percent` - Shows percentage (e.g., "42%") - default
  - `status_and_pages` - Shows pages read/total (e.g., "123/456")
  - `status_percent_and_pages` - Shows both (e.g., "123/456 (27%)")
- Only displays for in-progress books (not complete/abandoned status)
- Falls back to percentage if page count unavailable

Both features are configurable via the plugin menu under Advanced settings → Book display.

### User Patches

The plugin is designed to be customizable via KOReader's user patch system:
- Template provided in `resources/2-userpatch-template.lua`
- User patches can modify any aspect of the plugin by accessing internal modules
- Patches targeting the original Cover Browser plugin may still work
- Example patch file: `resources/2-font-override.lua`
- Useful current patch points include:
  - `ptutil.findCover()`, `ptutil.getFolderCover()`, and `ptutil.query_cover_paths()` for folder-cover behavior
  - `ptutil.formatProgressText()` and `ptutil.formatFooterText()` for display text customization
  - `BookInfoManager.max_cover_dimen` for extracted cover sizing

## Build and Release Commands

```bash
# Unix/Mac
./build-release-zip.sh

# Windows
build-release-zip.cmd
```

The build script:
1. Compiles `.po` translation files to `.mo` files using gettext tools (requires `xgettext`, `msgmerge`, `msgfmt`)
2. Creates `projecttitle.koplugin` directory
3. Copies all `.lua` files, `fonts/`, `icons/`, `resources/`, `l10n/` into the plugin folder
4. Creates `projecttitle.zip` for distribution
5. Cleans up temporary files

**Prerequisites**:
- Gettext tools (for translation compilation)
- zip or 7z (for archive creation)

The script auto-detects your OS and provides appropriate installation commands if dependencies are missing. Supports macOS, Debian/Ubuntu, Fedora/RHEL, Arch Linux, openSUSE, and other Unix systems.

## Testing

The project uses [Busted](https://lunarmodules.github.io/busted/) for unit testing.

**Run all tests**:
```bash
busted
```

**Run specific test file**:
```bash
busted spec/listmenu_spec.lua
```

**Test files**:
- `spec/support/mock_ui.lua` - Mocks for KOReader UI widgets
- `spec/*_spec.lua` - Test suites for individual modules

Tests use mocked KOReader widgets since the plugin depends on KOReader's UI framework. The mock system in `spec/support/mock_ui.lua` simulates FrameContainer, TextWidget, ImageWidget, etc.

## Development Notes

### KOReader Reference Checkout
- `REFERENCE/koreader/` is the local authority for current KOReader APIs and implementation patterns
- Inspect the relevant KOReader source before changing FileChooser, PathChooser, FileManager, Menu, font, or lifecycle integration
- The reference checkout is development-only and must not be included in release artifacts

### Font Management
- Fonts must be installed to `koreader/fonts/source/` directory
- Font references use paths relative to fonts directory (e.g., `source/SourceSerif4-Regular.ttf`)
- Font face loading uses KOReader's Font:getFace() which auto-scales by screen size

### Settings Storage
- Plugin settings stored in BookInfoManager database `config` table
- KOReader global settings accessed via G_reader_settings
- Setting keys use descriptive names (e.g., `hide_file_info`, `show_progress_in_mosaic`)
- Settings are versioned with `config_version` (currently 12) to support automatic migration

### Performance Considerations
- Cover image extraction can be slow, especially with many files
- Database queries are optimized with indexes on `directory, filename`
- Folder-cover candidates use bounded deterministic database scans and batch hydration
- Rendering uses a cached `render_context` to avoid repeated settings lookups in hot paths
- Decompressed covers are cached in a byte-budgeted KOReader `Cache` in `bookinfomanager.lua`
- `ptutil.lua` includes widget-pool and font-size-cache helpers used by the performance work on `sane`
- Cache can be pruned (removes deleted files) or emptied completely

### Localization
- Uses KOReader's gettext system: `require("l10n.gettext")`
- Translation files in `l10n/` directory as .po/.mo files
- 15+ languages supported

### Widget System
- Built on KOReader's widget framework
- Uses InputContainer, FrameContainer, TextWidget, ImageWidget, etc.
- Layout uses VerticalGroup, HorizontalGroup, OverlapGroup
- Gesture handling via GestureRange (tap, hold, pinch, spread)

## Common Tasks

### Adjusting Layout Defaults

Modify values in ptutil.lua tables:
- List view: `ptutil.list_defaults`
- Grid view: `ptutil.grid_defaults`
- Footer: `ptutil.footer_defaults`

### Changing Fonts

Edit font paths in ptutil.lua:
- `ptutil.good_serif`, `ptutil.good_sans` for base fonts
- `ptutil.title_serif` for title font

Or provide a user patch that overrides Font:getFace() calls.

### Adding New Display Modes

1. Add the mode to `DISPLAY_MODES` in `main.lua`
2. Add it to `ProjectTitle.modes`
3. Implement UI in listmenu.lua or mosaicmenu.lua
4. Handle it in `setupFileManagerDisplayMode()` and the instance-scoped menu configuration path

### Modifying Metadata Display

Check these locations:
- List items: listmenu.lua ListMenuItem:update()
- Grid items: mosaicmenu.lua MosaicMenuItem:update()
- Grid title/author overlay: `mosaicmenu.lua` (controlled by `show_mosaic_titles`)
- Grid progress text: `mosaicmenu.lua` (controlled by `progress_text_format`)
- Formatting helpers: ptutil.lua formatAuthors(), formatSeries(), formatAuthorSeries()

### Database Schema Changes

If modifying bookinfomanager.lua schema:
1. Update BOOKINFO_DB_VERSION
2. Update BOOKINFO_DB_SCHEMA
3. Update BOOKINFO_COLS_SET array
4. Implement migration if needed

## Gestures and Dispatcher Actions

The plugin registers these dispatcher actions in `main.lua`:
- `dec_items_pp` / `inc_items_pp` - Adjust items per page (pinch/spread gestures)
- `switch_grid` / `switch_list` - Switch display modes

These can be bound to gestures, buttons, or keyboard shortcuts via KOReader's dispatcher.

## Testing Considerations

- Test with books that have metadata and covers
- Test with books lacking metadata or covers
- Test folder navigation and folder cover generation
- Test with various screen sizes/orientations (portrait/landscape)
- Test on target platforms: Kobo, Kindle, Android, PocketBook
- Verify font installation on fresh install
- Check settings migration from older versions

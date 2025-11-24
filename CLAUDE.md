# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Project: Title is a KOReader plugin (written in Lua) that enhances the file browser interface with a modern, visually-rich UI. It replaces the default Cover Browser plugin by providing multiple display modes for books with metadata-rich views, cover images, and extensive customization options.

**Key Concept**: This plugin must identify itself as "coverbrowser" to KOReader (see _meta.lua:5) because core KOReader makes explicit calls to that plugin name, but the actual plugin name is "projecttitle".

## Architecture

### Plugin Loading and Initialization (main.lua)

The plugin follows a strict initialization sequence:

1. **Compatibility checks** (main.lua:26-66):
   - Checks if Cover Browser is disabled (required)
   - Verifies fonts are installed in `koreader/fonts/source/`
   - Verifies icons are installed in `koreader/icons/`
   - Validates KOReader version matches `safe_version` (currently 202510000000)
   - Can skip version check with `pt-skipversioncheck.txt` file

2. **Settings migration** (main.lua:208-280):
   - Uses versioned config migrations (`config_version` 1-7)
   - Current version 7 (as of latest update)
   - Version history:
     - v6: Introduced `progress_text_format` (replaced `show_pages_read_as_progress`)
     - v7: Introduced `show_mosaic_titles`
   - Migrates settings as new features are added
   - May trigger a KOReader restart if needed

3. **Method patching** (main.lua:861-960):
   - Saves original KOReader methods as locals at module load time
   - Replaces FileChooser, FileManager, and Menu methods based on display mode
   - Can restore original methods when switching back to classic mode

### Display Modes

The plugin supports 4 display modes (main.lua:133-139):
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
- Provides settings storage in `config` table

**covermenu.lua**: Generic menu implementation
- Replaces FileChooser.updateItems, FileChooser.onCloseWidget
- Implements genItemTable() to build file/folder lists
- Implements setupLayout() for title bar with navigation buttons
- Implements updatePageInfo() for footer with page controls and status info

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
- Helper functions: installFonts(), installIcons(), getFolderCover(), getSubfolderCoverImages()
- Formatting functions: formatAuthors(), formatSeries(), formatAuthorSeries(), formatTags()

**titlebar.lua**: Custom title bar with navigation buttons (up folder, favorites, history, last document)

**altbookstatuswidget.lua**: Alternative book status/screensaver screen with enhanced layout

**ptdbg.lua**: Debug logging utilities with consistent log prefix

### Folder Cover Generation

The plugin can auto-generate folder covers in two ways (ptutil.lua:230-509):

1. **Custom folder image**: Looks for `cover.*` or `folder.*` (jpg/png/webp/gif) in the directory
2. **Thumbnail grid**: Queries database for up to 16 random books with covers, displays as:
   - 2×2 grid layout (default)
   - Diagonal stacked layout (if `use_stacked_foldercovers` enabled)

### Mosaic/Grid View Book Display

**Title and Author Overlay** (`show_mosaic_titles`, mosaicmenu.lua:774-916):
- Displays title and author text above book covers in grid view
- Added in config version 7, enabled by default
- Uses filename as fallback when title is missing or contains only whitespace (including Unicode whitespace like non-breaking spaces)
- Text appears in a centered, framed container above the cover
- Intelligently reserves vertical space (max 40% of item height) while maintaining minimum cover height (60% of item height or 60px minimum)
- If text doesn't fit within constraints, the overlay is dropped entirely to preserve cover visibility

**Progress Bar Text Display** (`progress_text_format`, mosaicmenu.lua:1230-1270):
- Controls text shown alongside progress bars below covers (only when `hide_file_info` is true)
- Added in config version 6, replacing the older `show_pages_read_as_progress` setting
- Four display options:
  - `status_only` - Progress bar only, no text
  - `status_and_percent` - Shows percentage (e.g., "42%") - default
  - `status_and_pages` - Shows pages read/total (e.g., "123/456")
  - `status_percent_and_pages` - Shows both (e.g., "123/456 (27%)")
- Only displays for in-progress books (not complete/abandoned status)
- Falls back to percentage if page count unavailable

Both features are configurable via the plugin menu under Advanced settings → Book display (main.lua:556-636).

### User Patches

The plugin is designed to be customizable via KOReader's user patch system:
- Template provided in `resources/2-userpatch-template.lua`
- User patches can modify any aspect of the plugin by accessing internal modules
- Patches targeting the original Cover Browser plugin may still work
- See `resources/2-font-override.lua` and `resources/2-reader-footer-font-override.lua` for examples

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

### Font Management
- Fonts must be installed to `koreader/fonts/source/` directory
- Font references use paths relative to fonts directory (e.g., `source/SourceSerif4-Regular.ttf`)
- Font face loading uses KOReader's Font:getFace() which auto-scales by screen size

### Settings Storage
- Plugin settings stored in BookInfoManager database `config` table
- KOReader global settings accessed via G_reader_settings
- Setting keys use descriptive names (e.g., `hide_file_info`, `show_progress_in_mosaic`)
- Settings are versioned with `config_version` (currently 7) to support automatic migration

### Performance Considerations
- Cover image extraction can be slow, especially with many files
- Database queries are optimized with indexes on `directory, filename`
- Cover thumbnails for folders query database with `ORDER BY RANDOM() LIMIT 16`
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

1. Add mode to DISPLAY_MODES table (main.lua:133)
2. Add to modes list in CoverBrowser.modes (main.lua:156)
3. Implement UI in listmenu.lua or mosaicmenu.lua
4. Handle mode in setupFileManagerDisplayMode() (main.lua:861)

### Modifying Metadata Display

Check these locations:
- List items: listmenu.lua ListMenuItem:update()
- Grid items: mosaicmenu.lua MosaicMenuItem:update()
- Grid title/author overlay: mosaicmenu.lua:774-916 (controlled by `show_mosaic_titles`)
- Grid progress text: mosaicmenu.lua:1230-1270 (controlled by `progress_text_format`)
- Formatting helpers: ptutil.lua formatAuthors(), formatSeries(), formatAuthorSeries()

### Database Schema Changes

If modifying bookinfomanager.lua schema:
1. Update BOOKINFO_DB_VERSION
2. Update BOOKINFO_DB_SCHEMA
3. Update BOOKINFO_COLS_SET array
4. Implement migration if needed

## Gestures and Dispatcher Actions

The plugin registers dispatcher actions (main.lua:165-194):
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

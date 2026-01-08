local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local ImageWidget = require("ui/widget/imagewidget")
local LineWidget = require("ui/widget/linewidget")
local Size = require("ui/size")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local OverlapGroup = require("ui/widget/overlapgroup")
local logger = require("logger")
local Device = require("device")
local Screen = Device.screen
local BD = require("ui/bidi")
local T = require("ffi/util").template
local DataStorage = require("datastorage")
local ffiUtil = require("ffi/util")
local util = require("util")
local lfs = require("libs/libkoreader-lfs")
local _ = require("l10n.gettext")
local ptdbg = require("ptdbg")
local BookInfoManager = require("bookinfomanager")


--[[
    The settings and functions in this file are to intended make user patches easier.
    I strongly recommend writing a user patch rather than editing this file directly.
    Changes made to this file will be lost when upgrading. User patches are forever.

    For more information and examples visit this wiki article:

    https://github.com/joshuacant/ProjectTitle/wiki/User-Patches-for-Project-Title
--]]


local ptutil = {}

-- Folder cover widget cache
-- Caches generated folder cover widgets by folder path and dimensions
-- This avoids repeated database queries and widget tree construction
-- Cache key format: "filepath|max_w|max_h"
local folder_cover_cache = {}
local FOLDER_COVER_CACHE_SIZE = 50  -- Max cached folder covers

-- Clear the folder cover cache (called when menu closes or settings change)
-- NOTE: We don't call widget:free() here because the widgets might still be
-- referenced by menu items that haven't been garbage collected yet.
-- The GC will clean them up when all references are gone.
function ptutil.clearFolderCoverCache()
    folder_cover_cache = {}
end

-- Get cache key for folder cover
local function get_folder_cache_key(filepath, max_w, max_h)
    return filepath .. "|" .. tostring(max_w) .. "|" .. tostring(max_h)
end

-- Get cached folder cover widget
local function get_cached_folder_cover(filepath, max_w, max_h)
    local key = get_folder_cache_key(filepath, max_w, max_h)
    return folder_cover_cache[key]
end

-- Cache a folder cover widget
local function cache_folder_cover(filepath, max_w, max_h, widget)
    -- Simple size limit - remove oldest entries if over limit
    -- NOTE: We don't call old_widget:free() because it might still be in use
    -- by menu items that haven't been garbage collected yet.
    local count = 0
    for _ in pairs(folder_cover_cache) do count = count + 1 end
    if count >= FOLDER_COVER_CACHE_SIZE then
        -- Remove first entry (simple approach, not LRU)
        for key, _ in pairs(folder_cover_cache) do
            folder_cover_cache[key] = nil
            break
        end
    end
    local key = get_folder_cache_key(filepath, max_w, max_h)
    folder_cover_cache[key] = widget
end

ptutil.list_defaults = {
    -- Progress bar settings
    progress_bar_max_size = 235,      -- maximum progress bar width in pixels
    progress_bar_pages_per_pixel = 3, -- pixels per page for progress bar calculation
    progress_bar_min_size = 25,       -- minimum progress bar width in pixels

    -- Author display settings
    authors_limit_default = 2,     -- maximum number of authors to show
    authors_limit_with_series = 1, -- maximum authors when series is also shown on separate line

    -- Font size adjustment step (used when fitting text into available space)
    fontsize_dec_step = 2, -- font size decrement step when adjusting to fit

    -- Font size ranges (nominal sizes based on 64px item height)
    directory_font_nominal = 20, -- nominal directory font size
    directory_font_max = 26,     -- maximum directory font size
    title_font_nominal = 20,     -- nominal title font size
    title_font_max = 26,         -- maximum title font size
    title_font_min = 20,         -- minimum title font size
    authors_font_nominal = 14,   -- nominal authors/metadata font size
    authors_font_max = 18,       -- maximum authors font size
    authors_font_min = 10,       -- minimum authors font size
    wright_font_nominal = 11,    -- nominal right widget font size (reduced for better spacing)
    wright_font_max = 16,        -- maximum right widget font size (reduced for better spacing)

    -- calibre tags/keywords
    tags_font_min = 10,   -- minimum tags font size
    tags_font_offset = 3, -- offset from authors font size for tags
    tags_limit = 9999,    -- limits the number of tags displayed when enabled

    -- Page item limits
    max_items_per_page = 10,
    min_items_per_page = 3,
    default_items_per_page = 7,
}

-- These values adjust defaults and limits for the Cover Grid view
ptutil.grid_defaults = {
    -- Progress bar settings
    progress_bar_max_size = ptutil.list_defaults.progress_bar_max_size,               -- maximum progress bar width in pixels
    progress_bar_pages_per_pixel = ptutil.list_defaults.progress_bar_pages_per_pixel, -- pixels per page for progress bar calculation
    progress_bar_min_size = 40,                                                       -- minimum progress bar width in pixels

    -- Font size adjustment step (used when fitting text into available space)
    fontsize_dec_step = 1, -- font size decrement step when adjusting to fit

    -- Font size ranges (nominal sizes based on 64px item height)
    dir_font_nominal = 22, -- nominal directory font size
    dir_font_min = 18,     -- minimum directory font size

    -- Page item limits
    max_cols = 4,
    max_rows = 4,
    min_cols = 2,
    min_rows = 2,
    default_cols = 3,
    default_rows = 3,

    -- Cover Art display
    stretch_covers = false,
    stretch_ratio = 1,
}

ptutil.footer_defaults = {
    font_size = 20,
    font_size_deviceinfo = 18,
}

ptutil.bookstatus_defaults = {
    header_font_size = 20,
    metainfo_font_size = 18,
    title_font_size = 24,
    description_font_size = Screen:scaleBySize(18),
}

ptutil.good_serif = "source/SourceSerif4-Regular.ttf"
ptutil.good_serif_it = "source/SourceSerif4-It.ttf"
ptutil.good_serif_bold = "source/SourceSerif4-Bold.ttf"
ptutil.good_serif_boldit = "source/SourceSerif4-BoldIt.ttf"
ptutil.good_sans = "source/SourceSans3-Regular.ttf"
ptutil.good_sans_it = "source/SourceSans3-It.ttf"
ptutil.good_sans_bold = "source/SourceSans3-Bold.ttf"
ptutil.good_sans_boldit = "source/SourceSans3-BoldIt.ttf"
ptutil.title_serif = ptutil.good_serif_boldit

-- a non-standard space is used here because it looks nicer
ptutil.separator = {
    bar     = " | ",
    bullet  = " • ",
    comma   = ", ", -- except here
    dot     = " · ",
    em_dash = " — ",
    en_dash = " - ",
}

ptutil.koreader_dir = DataStorage:getDataDir()

function ptutil.getPluginDir()
    local callerSource = debug.getinfo(2, "S").source
    if callerSource:find("^@") then
        return callerSource:gsub("^@(.*)/[^/]*", "%1")
    end
end

local function copyRecursive(from, to)
    -- from: koreader/frontend/apps/filemanager/filemanager.lua
    local cp_bin = Device:isAndroid() and "/system/bin/cp" or "/bin/cp"
    return ffiUtil.execute(cp_bin, "-r", from, to ) == 0
end

function ptutil.installFonts()
    local fonts_path = ptutil.koreader_dir .. "/fonts"
    local function checkfonts()
        logger.info(ptdbg.logprefix, "Checking for fonts")
        if util.fileExists(fonts_path .. "/source/SourceSans3-Regular.ttf") and
            util.fileExists(fonts_path .. "/source/SourceSerif4-Regular.ttf") and
            util.fileExists(fonts_path .. "/source/SourceSerif4-BoldIt.ttf") then
            logger.info(ptdbg.logprefix, "Fonts found")
            return true
        else
            return false
        end
    end

    if checkfonts() then return true end

    local result
    if not util.directoryExists(fonts_path) then
        result = util.makePath(ptutil.koreader_dir .. "/fonts/")
        logger.info(ptdbg.logprefix, "Creating fonts folder")
        if not result then return false end
    end
    if util.directoryExists(fonts_path) then
        -- copy the entire "source"
        result = copyRecursive(ptutil.getPluginDir() .. "/fonts/source", fonts_path)
        logger.info(ptdbg.logprefix, "Copying fonts")
        if not result then return false end
        package.loaded["ui/font"] = nil
    end

    if checkfonts() then return true end
    return false
end

function ptutil.installIcons()
    local icons_path = ptutil.koreader_dir .. "/icons"
    local icons_list = {
        "favorites",
        "go_up",
        "hero",
        "history",
        "last_document",
        "plus",
    }
    local function checkicons()
        logger.info(ptdbg.logprefix, "Checking for icons")
        local icons_found = true
        for _, icon in ipairs(icons_list) do
            local icon_file = icons_path .. "/" .. icon .. ".svg"
            if not util.fileExists(icon_file) then
                icons_found = false
            end
        end
        if icons_found then
            logger.info(ptdbg.logprefix, "All icons found")
            return true
        else
            return false
        end
    end

    if checkicons() then return true end

    local result
    if not util.directoryExists(icons_path) then
        result = util.makePath(ptutil.koreader_dir .. "/icons/")
        logger.info(ptdbg.logprefix, "Creating icons folder")
        if not result then return false end
    end

    if util.directoryExists(icons_path) then
        for _, icon in ipairs(icons_list) do
            -- check icon files one at a time, and only copy when missing
            -- this will preserve custom icons set by the user
            local icon_file = icons_path .. "/" .. icon .. ".svg"
            if not util.fileExists(icon_file) then
                local bundled_icon_file = ptutil.getPluginDir() .. "/icons/" .. icon .. ".svg"
                logger.info(ptdbg.logprefix, "Copying icon")
                ffiUtil.copyFile(bundled_icon_file, icon_file)
            end
        end
        package.loaded["ui/widget/iconwidget"] = nil
        package.loaded["ui/widget/iconbutton"] = nil
    end

    if checkicons() then return true end
    return false
end

local function findCover(dir_path)
    if not dir_path or dir_path == "" or dir_path == ".." or dir_path:match("%.%.$") then
        return nil
    end

    dir_path = dir_path:gsub("[/\\]+$", "")
    if not util.directoryExists(dir_path) then return nil end

    local fn_lc
    for fn in lfs.dir(dir_path) do
        fn_lc = fn:lower()
        if fn_lc:match('^%.?cover%.') or fn_lc:match('^%.?folder%.') then
            if fn_lc:match('%.jpe?g$') or fn_lc:match('%.png$') or fn_lc:match('%.webp$') or fn_lc:match('%.gif$') then
                return dir_path .. "/" .. fn
            end
        end
    end
    return nil
end

function ptutil.getFolderCover(filepath, max_img_w, max_img_h)
    local folder_image_file = findCover(filepath)
    if folder_image_file ~= nil then
        local success, folder_image = pcall(function()
            local temp_image = ImageWidget:new { file = folder_image_file, scale_factor = 1 }
            temp_image:_render()
            local orig_w = temp_image:getOriginalWidth()
            local orig_h = temp_image:getOriginalHeight()
            temp_image:free()
            local scale_to_fill = 0
            if orig_w and orig_h then
                local scale_x = max_img_w / orig_w
                local scale_y = max_img_h / orig_h
                scale_to_fill = math.max(scale_x, scale_y)
            end
            return ImageWidget:new {
                file = folder_image_file,
                width = max_img_w,
                height = max_img_h,
                scale_factor = scale_to_fill,
                center_x_ratio = 0.5,
                center_y_ratio = 0.5,
            }
        end)
        if success then
            return FrameContainer:new {
                width = max_img_w,
                height = max_img_h,
                margin = 0,
                padding = 0,
                bordersize = 0,
                folder_image
            }
        else
            logger.info(ptdbg.logprefix, "Folder cover found but failed to render, could be too large or broken:",
                folder_image_file)
            local size_mult = 1.25
            local _, _, scale_factor = BookInfoManager.getCachedCoverSize(250, 500, max_img_w * size_mult,
                max_img_h * size_mult)
            return FrameContainer:new {
                width = max_img_w * size_mult,
                height = max_img_h * size_mult,
                margin = 0,
                padding = 0,
                bordersize = 0,
                ImageWidget:new {
                    file = ptutil.getPluginDir() .. "/resources/file-unsupported.svg",
                    alpha = true,
                    scale_factor = scale_factor,
                    original_in_nightmode = false,
                }
            }
        end
    else
        return nil
    end
end

local function query_cover_paths(folder, include_subfolders)
    if not util.directoryExists(folder) then return nil end

    -- Reuse BookInfoManager's database connection instead of opening our own
    BookInfoManager:openDbConnection()
    local db_conn = BookInfoManager.db_conn

    -- If BookInfoManager connection is unavailable, we can't proceed safely
    -- (Opening our own connection would leak since we wouldn't track it)
    if not db_conn then
        return nil
    end

    local query
    folder = folder:gsub("'", "''")
    folder = folder:gsub(";","_") -- ljsqlite3 splits commands on semicolons
    if include_subfolders then
        query = string.format([[
            SELECT directory, filename FROM bookinfo
            WHERE directory LIKE '%s/%%' AND has_cover = 'Y'
            ORDER BY RANDOM() LIMIT 16;
            ]], folder)
    else
        query = string.format([[
            SELECT directory, filename FROM bookinfo
            WHERE directory = '%s/' AND has_cover = 'Y'
            ORDER BY RANDOM() LIMIT 16;
            ]], folder)
    end

    local res = db_conn:exec(query)
    -- Don't close - we're reusing BookInfoManager's connection
    return res
end

local function get_thumbnail_size(max_w, max_h)
    local max_img_w = 0
    local max_img_h = 0
    if BookInfoManager:getSetting("use_stacked_foldercovers") then
        max_img_w = (max_w * 0.75) - (Size.border.thin * 2) - Size.padding.default
        max_img_h = (max_h * 0.75) - (Size.border.thin * 2) - Size.padding.default
    else
        max_img_w = (max_w - (Size.border.thin * 4) - Size.padding.small) / 2
        max_img_h = (max_h - (Size.border.thin * 4) - Size.padding.small) / 2
    end
    return max_img_w, max_img_h
end

local function build_cover_images(db_res, max_w, max_h)
    local covers = {}
    if db_res then
        local directories = db_res[1]
        local filenames = db_res[2]
        local max_img_w, max_img_h = get_thumbnail_size(max_w, max_h)
        for i, filename in ipairs(filenames) do
            local fullpath = directories[i] .. filename
            if util.fileExists(fullpath) then
                local bookinfo = BookInfoManager:getBookInfo(fullpath, true)
                if bookinfo and bookinfo.cover_bb then
                    local border_total = (Size.border.thin * 2)
                    local _, _, scale_factor = BookInfoManager.getCachedCoverSize(
                        bookinfo.cover_w, bookinfo.cover_h, max_img_w, max_img_h)
                    local wimage = ImageWidget:new {
                        image = bookinfo.cover_bb,
                        image_disposable = false, -- Don't free cached cover_bb
                        scale_factor = scale_factor,
                    }
                    table.insert(covers, FrameContainer:new {
                        width = math.floor((bookinfo.cover_w * scale_factor) + border_total),
                        height = math.floor((bookinfo.cover_h * scale_factor) + border_total),
                        margin = 0,
                        padding = 0,
                        radius = Size.radius.default,
                        bordersize = Size.border.thin,
                        color = Blitbuffer.COLOR_GRAY_3,
                        background = Blitbuffer.COLOR_GRAY_3,
                        wimage,
                    })
                end
                if #covers == 4 then break end
            end
        end
    end
    return covers
end

-- Helper to create a blank frame-style cover with background
local function create_blank_cover(width, height, background_idx)
    local backgrounds = {
        Blitbuffer.COLOR_LIGHT_GRAY,
        Blitbuffer.COLOR_GRAY_D,
        Blitbuffer.COLOR_GRAY_E,
    }
    local max_img_w = width - (Size.border.thin * 2)
    local max_img_h = height - (Size.border.thin * 2)
    return FrameContainer:new {
        width = width,
        height = height,
        radius = Size.radius.default,
        margin = 0,
        padding = 0,
        bordersize = Size.border.thin,
        color = Blitbuffer.COLOR_DARK_GRAY,
        background = backgrounds[background_idx],
        CenterContainer:new {
            dimen = Geom:new { w = max_img_w, h = max_img_h },
            HorizontalSpan:new { width = max_img_w, height = max_img_h },
        }
    }
end

-- Build the diagonal stack layout using OverlapGroup
local function build_diagonal_stack(images, max_w, max_h)
    local top_image_size = images[#images]:getSize()
    local nb_fakes = (4 - #images)
    for i = 1, nb_fakes do
        table.insert(images, 1, create_blank_cover(top_image_size.w, top_image_size.h, (i % 2 + 2)))
    end

    local stack_items = {}
    local stack_width = 0
    local stack_height = 0
    local inset_left = 0
    local inset_top = 0
    for _, img in ipairs(images) do
        local frame = FrameContainer:new {
            margin = 0,
            bordersize = 0,
            padding = nil,
            padding_left = inset_left,
            padding_top = inset_top,
            img,
        }
        stack_width = math.max(stack_width, frame:getSize().w)
        stack_height = math.max(stack_height, frame:getSize().h)
        inset_left = inset_left + (max_w * 0.08)
        inset_top = inset_top + (max_h * 0.08)
        table.insert(stack_items, frame)
    end

    local stack = OverlapGroup:new {
        dimen = Geom:new { w = stack_width, h = stack_height },
    }
    table.move(stack_items, 1, #stack_items, #stack + 1, stack)
    local centered_stack = CenterContainer:new {
        dimen = Geom:new { w = max_w, h = max_h },
        stack,
    }
    return centered_stack
end

-- Build a 2x2 grid layout using nested horizontal & vertical groups
local function build_grid(images, max_w, max_h)
    local row1 = HorizontalGroup:new {}
    local row2 = HorizontalGroup:new {}
    local layout = VerticalGroup:new {}

    -- Create blank covers if needed
    if #images == 3 then
        local w3, h3 = images[3]:getSize().w, images[3]:getSize().h
        table.insert(images, 2, create_blank_cover(w3, h3, 3))
    elseif #images == 2 then
        local w1, h1 = images[1]:getSize().w, images[1]:getSize().h
        local w2, h2 = images[2]:getSize().w, images[2]:getSize().h
        table.insert(images, 2, create_blank_cover(w1, h1, 3))
        table.insert(images, 3, create_blank_cover(w2, h2, 2))
    elseif #images == 1 then
        local w1, h1 = images[1]:getSize().w, images[1]:getSize().h
        table.insert(images, 1, create_blank_cover(w1, h1, 3))
        table.insert(images, 2, create_blank_cover(w1, h1, 2))
        table.insert(images, 4, create_blank_cover(w1, h1, 3))
    end

    for i, img in ipairs(images) do
        if i < 3 then
            table.insert(row1, img)
        else
            table.insert(row2, img)
        end
        if i == 1 then
            table.insert(row1, HorizontalSpan:new { width = Size.padding.small })
        elseif i == 3 then
            table.insert(row2, HorizontalSpan:new { width = Size.padding.small })
        end
    end

    table.insert(layout, row1)
    table.insert(layout, VerticalSpan:new { width = Size.padding.small })
    table.insert(layout, row2)
    return layout
end

function ptutil.getSubfolderCoverImages(filepath, max_w, max_h)
    -- Return nil early if filepath is nil
    if not filepath then return nil end

    -- NOTE: We intentionally don't use the folder cover widget cache here.
    -- Widgets are owned by their parent widget and get freed when the parent
    -- is freed. Caching and reusing widgets across different parents causes
    -- use-after-free crashes when swiping between pages.

    local db_res = query_cover_paths(filepath, false)
    local images = build_cover_images(db_res, max_w, max_h)

    if #images < 4 then
        db_res = query_cover_paths(filepath, true)
        images = build_cover_images(db_res, max_w, max_h)
    end

    -- Return nil if no images found
    if #images == 0 then return nil end

    local result
    if BookInfoManager:getSetting("use_stacked_foldercovers") then
        result = build_diagonal_stack(images, max_w, max_h)
    else
        result = build_grid(images, max_w, max_h)
    end

    return result
end

function ptutil.line(width, color, thickness)
    return HorizontalGroup:new {
        HorizontalSpan:new { width = Screen:scaleBySize(10) },
        LineWidget:new {
            dimen = Geom:new { w = width - Screen:scaleBySize(20), h = thickness },
            background = color,
        },
        HorizontalSpan:new { width = Screen:scaleBySize(10) },
    }
end

ptutil.thinWhiteLine = function(w) return ptutil.line(w, Blitbuffer.COLOR_WHITE,  Size.line.thin) end
ptutil.thinGrayLine = function(w) return ptutil.line(w, Blitbuffer.COLOR_GRAY,  Size.line.thin) end
ptutil.thinBlackLine  = function(w) return ptutil.line(w, Blitbuffer.COLOR_BLACK, Size.line.thin) end
ptutil.mediumBlackLine  = function(w) return ptutil.line(w, Blitbuffer.COLOR_BLACK, Size.line.medium) end

function ptutil.onFocus(_underline_container, render_context)
    -- Use ~= nil check to properly handle explicit false values from render_context
    local is_touch = (render_context and render_context.is_touch_device ~= nil) and render_context.is_touch_device or Device:isTouchDevice()
    local force_indicator = (render_context and render_context.force_focus_indicator ~= nil) and render_context.force_focus_indicator or BookInfoManager:getSetting("force_focus_indicator")
    if not is_touch or force_indicator then
        _underline_container.color = Blitbuffer.COLOR_BLACK
    end
end

function ptutil.onUnfocus(_underline_container, render_context)
    -- Use ~= nil check to properly handle explicit false values from render_context
    local is_touch = (render_context and render_context.is_touch_device ~= nil) and render_context.is_touch_device or Device:isTouchDevice()
    local force_indicator = (render_context and render_context.force_focus_indicator ~= nil) and render_context.force_focus_indicator or BookInfoManager:getSetting("force_focus_indicator")
    if not is_touch or force_indicator then
        _underline_container.color = Blitbuffer.COLOR_WHITE
    end
end

function ptutil.showProgressBar(pages, render_context)
    local show_progress_bar = false
    local est_page_count = pages or nil

    -- Use ~= nil check to properly handle explicit false values from render_context
    local force_max = (render_context and render_context.force_max_progressbars ~= nil) and render_context.force_max_progressbars or BookInfoManager:getSetting("force_max_progressbars")
    local show_pages_read = (render_context and render_context.show_pages_read_as_progress ~= nil) and render_context.show_pages_read_as_progress or BookInfoManager:getSetting("show_pages_read_as_progress")
    local hide_file_info = (render_context and render_context.hide_file_info ~= nil) and render_context.hide_file_info or BookInfoManager:getSetting("hide_file_info")
    local force_no = (render_context and render_context.force_no_progressbars ~= nil) and render_context.force_no_progressbars or BookInfoManager:getSetting("force_no_progressbars")

    if force_max and not show_pages_read then
        est_page_count = ptutil.list_defaults.progress_bar_pages_per_pixel * ptutil.list_defaults.progress_bar_max_size
    end
    show_progress_bar = est_page_count ~= nil and
        hide_file_info and                    -- "show file info"
        not show_pages_read and               -- "show pages read"
        not force_no                          -- "show progress %"
    return est_page_count, show_progress_bar
end

function ptutil.isPathChooser(self)
    local is_pathchooser = false
    if (self.title_bar and self.title_bar.title ~= "") or (self.menu and self.menu.title ~= "") then
        is_pathchooser = true
    end
    return is_pathchooser
end

function ptutil.formatAuthors(authors, authors_limit)
    local formatted_authors = ""
    if authors and authors:find("\n") then
        local full_authors_list = util.splitToArray(authors, "\n")
        local nb_authors = #full_authors_list
        local final_authors_list = {}
        for i = 1, nb_authors do
            full_authors_list[i] = BD.auto(full_authors_list[i])
            if i == authors_limit and nb_authors > authors_limit then
                table.insert(final_authors_list, T(_("%1 et al."), full_authors_list[i]))
            else
                table.insert(final_authors_list, full_authors_list[i])
            end
            if i == authors_limit then break end
        end
        formatted_authors = table.concat(final_authors_list, "\n")
    elseif authors then
        formatted_authors = BD.auto(authors)
    end
    return formatted_authors
end

function ptutil.formatSeries(series, series_index)
    local formatted_series = ""
    -- suppress series if index is "0"
    if series_index == 0 then
        return ""
    end
    -- if series is formated like "big series: small subseries" then show only "small subseries"
    if string.match(series, ": ") then
        series = string.sub(series, util.lastIndexOf(series, ": ") + 1, -1)
    end
    if series_index then
        formatted_series = "#" .. series_index .. ptutil.separator.en_dash .. BD.auto(series)
    else
        formatted_series = BD.auto(series)
    end
    return formatted_series
end

function ptutil.formatAuthorSeries(authors, series, series_mode, show_tags)
    local formatted_author_series = ""
    if authors == nil or authors == "" then
        if series_mode == "series_in_separate_line" and series ~= "" then
            formatted_author_series = series
        end
    else
        if show_tags then
            local authors_list = util.splitToArray(authors, "\n")
            authors = table.concat(authors_list, ptutil.separator.comma)
        end
        if series_mode == "series_in_separate_line" and series ~= "" then
            if show_tags then
                formatted_author_series = authors .. ptutil.separator.dot .. series
            else
                formatted_author_series = authors .. "\n" .. series
            end
        else
            formatted_author_series = authors
        end
    end
    return formatted_author_series
end

-- Format tags/keywords coming from calibre/bookinfo.keywords
-- Expect keywords as newline-separated values. Return a compact
-- single-line string limited to `tags_limit` items or nil if no tags.
function ptutil.formatTags(keywords, tags_limit)
    if not keywords or keywords == "" then return nil end
    local final_tags_list = {}
    local full_list = util.splitToArray(keywords, "\n")
    local nb_tags = #full_list
    if nb_tags == 0 then return nil end
    tags_limit = tags_limit or 9999
    for i = 1, math.min(tags_limit, nb_tags) do
        local t = full_list[i]
        if t and t ~= "" then
            table.insert(final_tags_list, BD.auto(t))
        end
    end
    local formatted_tags = table.concat(final_tags_list, ptutil.separator.bullet)
    if nb_tags > tags_limit then
        formatted_tags = formatted_tags .. "…"
    end
    return formatted_tags
end

-- Font size estimation cache
-- Key format: "text_len|width|height|min|max"
local font_size_cache = {}
local FONT_SIZE_CACHE_MAX = 200

-- Clear the font size cache (e.g., on settings change or menu close)
function ptutil.clearFontSizeCache()
    font_size_cache = {}
end

-- Quick-fit detection: determine if text will definitely fit at max size
-- This allows skipping the sizing loop for simple cases
-- @param params Table with: text, width, height, max_size
-- @return boolean True if text will definitely fit at max size
function ptutil.isTextQuickFit(params)
    local text = params.text or ""
    local width = params.width or 100
    local height = params.height or 100
    local max_size = params.max_size or 26

    -- Heuristic: estimate characters per line at max font size
    -- Assume average character width is roughly 0.6 * font_size
    local avg_char_width = max_size * 0.6
    local chars_per_line = math.floor(width / avg_char_width)

    -- Estimate line height (roughly 1.2 * font_size)
    local line_height = max_size * 1.2
    local max_lines = math.floor(height / line_height)

    -- Total characters that can fit
    local max_chars = chars_per_line * max_lines

    -- If text length is well under the limit, it's a quick fit
    -- Use 60% threshold to account for word wrapping inefficiency
    local text_len = #text
    return text_len < (max_chars * 0.6)
end

-- Estimate optimal font size for text in given dimensions
-- Uses heuristics to avoid trial-and-error widget creation
-- @param params Table with: text, width, height, min_size, max_size
-- @return number Estimated font size
function ptutil.estimateFontSize(params)
    local text = params.text or ""
    local width = params.width or 100
    local height = params.height or 100
    local min_size = params.min_size or 10
    local max_size = params.max_size or 26

    -- Check cache first
    local text_len = #text
    -- Use math.floor to ensure all values are integers for the cache key
    local cache_key = string.format("%d|%d|%d|%d|%d", text_len, math.floor(width), math.floor(height), math.floor(min_size), math.floor(max_size))
    if font_size_cache[cache_key] then
        return font_size_cache[cache_key]
    end

    -- Quick fit check - use max size if text is short enough
    if ptutil.isTextQuickFit(params) then
        font_size_cache[cache_key] = max_size
        return max_size
    end

    -- Heuristic estimation based on text area requirements
    -- Target: text should fill roughly 60-80% of available area

    -- Count approximate lines based on newlines and text length
    local newline_count = 0
    for _ in text:gmatch("\n") do
        newline_count = newline_count + 1
    end

    -- Estimate how many lines we'll need
    -- Assume average character width is 0.6 * font_size
    -- and we want roughly 80% fill per line
    local target_fill = 0.8
    local char_width_ratio = 0.6
    local line_height_ratio = 1.3  -- Line height relative to font size

    -- Calculate available area
    local available_area = width * height

    -- Estimate required area for text at font size 1
    -- Each character needs roughly (0.6 * size) * (1.3 * size) = 0.78 * size^2
    local area_per_char_at_size_1 = char_width_ratio * line_height_ratio

    -- Total area needed at size 1
    local text_area_at_size_1 = text_len * area_per_char_at_size_1

    -- Solve for font size: text_area_at_size_1 * size^2 = target_fill * available_area
    -- size^2 = (target_fill * available_area) / text_area_at_size_1
    -- size = sqrt((target_fill * available_area) / text_area_at_size_1)
    local target_area = target_fill * available_area
    local size_squared = target_area / text_area_at_size_1
    local estimated_size = math.sqrt(size_squared)

    -- Account for line breaks - text with newlines needs less width
    -- but more height, so reduce estimate slightly
    if newline_count > 0 then
        estimated_size = estimated_size * (1 - newline_count * 0.05)
    end

    -- Clamp to min/max bounds
    estimated_size = math.max(min_size, math.min(max_size, math.floor(estimated_size)))

    -- Cache the result (with size limit)
    local cache_count = 0
    for _ in pairs(font_size_cache) do cache_count = cache_count + 1 end
    if cache_count >= FONT_SIZE_CACHE_MAX then
        -- Simple eviction: clear cache when full
        font_size_cache = {}
    end
    font_size_cache[cache_key] = estimated_size

    return estimated_size
end

-- Widget Pool for reducing widget allocations
-- Pools commonly used widgets like HorizontalSpan, VerticalSpan, FrameContainer
-- to avoid repeated creation and garbage collection overhead
local WidgetPool = {}
WidgetPool.__index = WidgetPool

-- Widget type to constructor mapping
local widget_constructors = nil -- Lazy-initialized

local function get_widget_constructors()
    if widget_constructors then return widget_constructors end
    widget_constructors = {
        HorizontalSpan = require("ui/widget/horizontalspan"),
        VerticalSpan = require("ui/widget/verticalspan"),
        FrameContainer = require("ui/widget/container/framecontainer"),
        CenterContainer = require("ui/widget/container/centercontainer"),
        LeftContainer = require("ui/widget/container/leftcontainer"),
    }
    return widget_constructors
end

-- Create a new widget pool
-- @param opts Table with options: max_per_type (default 20)
function WidgetPool:new(opts)
    opts = opts or {}
    local pool = {
        pools = {},  -- widget_type -> array of available widgets
        max_per_type = opts.max_per_type or 20,
    }
    setmetatable(pool, WidgetPool)
    return pool
end

-- Acquire a widget from the pool, creating a new one if none available
-- @param widget_type String name of widget type (e.g., "HorizontalSpan")
-- @param init_params Table of initialization parameters
-- @return Widget instance
function WidgetPool:acquire(widget_type, init_params)
    local type_pool = self.pools[widget_type]

    if type_pool and #type_pool > 0 then
        -- Reuse a pooled widget
        local widget = table.remove(type_pool)
        -- Reset widget properties with new init_params
        if init_params then
            for k, v in pairs(init_params) do
                widget[k] = v
            end
        end
        return widget
    end

    -- Create a new widget
    local constructors = get_widget_constructors()
    local constructor = constructors[widget_type]
    if constructor then
        return constructor:new(init_params or {})
    end

    -- Fallback: create a simple table if widget type not found
    local widget = init_params or {}
    widget._pool_type = widget_type
    return widget
end

-- Release a widget back to the pool for reuse
-- @param widget Widget instance to release
function WidgetPool:release(widget)
    if not widget then return end

    local widget_type = widget._pool_type or widget.name or "unknown"

    -- Initialize pool for this type if needed
    if not self.pools[widget_type] then
        self.pools[widget_type] = {}
    end

    local type_pool = self.pools[widget_type]

    -- Only pool if under the limit
    if #type_pool < self.max_per_type then
        -- Clear children to avoid holding references
        if widget.children then
            widget.children = {}
        end
        if widget[1] then
            widget[1] = nil
        end
        table.insert(type_pool, widget)
    end
    -- If over limit, widget will be garbage collected
end

-- Get the current size of the pool for a widget type
-- @param widget_type String name of widget type
-- @return Number of pooled widgets
function WidgetPool:getPoolSize(widget_type)
    local type_pool = self.pools[widget_type]
    if type_pool then
        return #type_pool
    end
    return 0
end

-- Clear all pooled widgets
function WidgetPool:clear()
    self.pools = {}
end

-- Export WidgetPool
ptutil.WidgetPool = WidgetPool

-- O(1) LRU Cache Implementation
-- Uses a doubly-linked list + hash map for O(1) get, put, and eviction
local LRUCache = {}
LRUCache.__index = LRUCache

-- Create a new LRU cache
-- @param max_size Maximum number of entries before eviction
function LRUCache:new(max_size)
    local cache = {
        max_size = max_size or 25,
        map = {},        -- key -> node
        head = nil,      -- Most recently used
        tail = nil,      -- Least recently used
        current_size = 0,
    }
    setmetatable(cache, LRUCache)
    return cache
end

-- Internal: Create a new node
local function create_node(key, value)
    return {
        key = key,
        value = value,
        prev = nil,
        next = nil,
    }
end

-- Internal: Remove a node from the linked list
function LRUCache:_remove_node(node)
    if node.prev then
        node.prev.next = node.next
    else
        self.head = node.next
    end

    if node.next then
        node.next.prev = node.prev
    else
        self.tail = node.prev
    end

    node.prev = nil
    node.next = nil
end

-- Internal: Add node to head (most recent)
function LRUCache:_add_to_head(node)
    node.next = self.head
    node.prev = nil

    if self.head then
        self.head.prev = node
    end

    self.head = node

    if not self.tail then
        self.tail = node
    end
end

-- Internal: Move node to head (mark as most recently used)
function LRUCache:_move_to_head(node)
    self:_remove_node(node)
    self:_add_to_head(node)
end

-- Get a value from the cache
-- @param key The key to look up
-- @return The cached value, or nil if not found
function LRUCache:get(key)
    local node = self.map[key]
    if not node then
        return nil
    end

    -- Move to head (most recently used)
    self:_move_to_head(node)

    return node.value
end

-- Put a value in the cache
-- @param key The key to store
-- @param value The value to store
function LRUCache:put(key, value)
    local node = self.map[key]

    if node then
        -- Update existing entry
        node.value = value
        self:_move_to_head(node)
    else
        -- Create new entry
        node = create_node(key, value)
        self.map[key] = node
        self:_add_to_head(node)
        self.current_size = self.current_size + 1

        -- Evict if over capacity
        if self.current_size > self.max_size then
            local evicted = self.tail
            if evicted then
                self:_remove_node(evicted)
                self.map[evicted.key] = nil
                self.current_size = self.current_size - 1
            end
        end
    end
end

-- Invalidate (remove) a specific key
-- @param key The key to remove
function LRUCache:invalidate(key)
    local node = self.map[key]
    if node then
        self:_remove_node(node)
        self.map[key] = nil
        self.current_size = self.current_size - 1
    end
end

-- Clear all entries
function LRUCache:clear()
    self.map = {}
    self.head = nil
    self.tail = nil
    self.current_size = 0
end

-- Get current cache size
function LRUCache:size()
    return self.current_size
end

-- Export LRUCache
ptutil.LRUCache = LRUCache

return ptutil

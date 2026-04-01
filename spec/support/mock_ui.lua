local function mock_widget(name)
    local Widget = {}
    Widget.__index = Widget

    function Widget:new(o)
        o = o or {}
        setmetatable(o, self)
        o.name = name
        o.children = {}
        -- Store children if passed in array part
        for i, v in ipairs(o) do
            table.insert(o.children, v)
        end
        if o.init then
            o:init()
        end
        return o
    end

    function Widget:extend(o)
        o = o or {}
        setmetatable(o, self)
        self.__index = self
        o.__index = o
        return o
    end

    function Widget:init() end

    function Widget:getSize()
        return { w = self.w or 100, h = self.h or 20 }
    end

    function Widget:free() end

    function Widget:paintTo() end

    function Widget:setText(text)
        self.text = text
    end

    function Widget:setMaxWidth(width)
        self.max_width = width
    end

    function Widget:getBaseline() return 15 end
    function Widget:getTextHeight() return 20 end
    function Widget:getLineHeight() return 20 end
    function Widget:isTruncated() return false end

    return Widget
end

local function setup_mocks()
    package.loaded["ui/bidi"] = {
        directory = function(s) return s end,
        filename = function(s) return s end,
        auto = function(s) return s end
    }
    package.loaded["ffi/blitbuffer"] = {
        COLOR_WHITE = 0,
        COLOR_BLACK = 1,
        COLOR_GRAY_2 = 2,
        COLOR_GRAY_3 = 3,
        COLOR_GRAY_E = 4,
        COLOR_DARK_GRAY = 5
    }
    
    package.loaded["ffi/util"] = {
        template = function(s, ...) 
            local args = {...}
            -- Simple mock for T template: replace %1, %2 etc with args
            local res = s
            for i, v in ipairs(args) do
                res = res:gsub("%%" .. i, tostring(v))
            end
            return res
        end,
        line = { thin = 1 },
        border = { thin = 1, default = 2 },
        padding = { small = 5, tiny = 2, default = 10 },
        margin = { fine_tune = 1 },
        copyFile = function(src, dest) return true end,
        execute = function(...) return 0 end
    }
    
    package.loaded["ui/size"] = {
        border = { thin = 1, default = 2, thick = 3 },
        padding = { small = 5, tiny = 2, default = 10 },
        line = { thin = 1, medium = 2 },
        radius = { default = 5 },
        margin = { fine_tune = 1, default = 10, tiny = 2 }
    }

    -- Mock FileManager
    package.loaded["apps/filemanager/filemanager"] = {
        instance = {
            file_chooser = {},
            menu = {}
        }
    }

    -- Mock DataStorage
    package.loaded["datastorage"] = {
        getSettingsDir = function() return "/tmp" end,
        getDataDir = function() return "/tmp/koreader" end
    }

    -- Mock SQ3
    package.loaded["lua-ljsqlite3/init"] = {
        open = function()
            return {
                close = function() end,
                set_busy_timeout = function() end,
                exec = function() return nil end
            }
        end
    }

    package.loaded["cache"] = {
        new = function(_, opts)
            local used_size = 0
            local entries = {}
            local access_counter = 0
            local cache

            local function entry_count()
                local count = 0
                for _ in pairs(entries) do
                    count = count + 1
                end
                return count
            end

            local function evict_if_needed()
                while opts.size and used_size > opts.size do
                    local lru_key
                    local lru_stamp
                    for key, entry in pairs(entries) do
                        if not lru_stamp or entry.stamp < lru_stamp then
                            lru_key = key
                            lru_stamp = entry.stamp
                        end
                    end
                    if not lru_key then
                        break
                    end
                    used_size = used_size - entries[lru_key].size
                    entries[lru_key] = nil
                end
            end

            cache = {
                size = opts.size,
                avg_itemsize = opts.avg_itemsize,
                slots = opts.slots or (opts.size and opts.avg_itemsize and math.ceil(opts.size / opts.avg_itemsize)) or nil,
                cache = {
                    get = function(_, key)
                        local entry = entries[key]
                        if not entry then
                            return nil
                        end
                        access_counter = access_counter + 1
                        entry.stamp = access_counter
                        return entry.value
                    end,
                    set = function(_, key, value, size)
                        local entry_size = size or 0
                        if entries[key] then
                            used_size = used_size - entries[key].size
                        end
                        access_counter = access_counter + 1
                        entries[key] = {
                            value = value,
                            size = entry_size,
                            stamp = access_counter,
                        }
                        used_size = used_size + entry_size
                        evict_if_needed()
                    end,
                    delete = function(_, key)
                        if entries[key] then
                            used_size = used_size - entries[key].size
                            entries[key] = nil
                        end
                    end,
                    clear = function()
                        entries = {}
                        used_size = 0
                    end,
                    used_size = function()
                        return used_size
                    end,
                    used_slots = function()
                        return entry_count()
                    end,
                    pairs = function()
                        return next, entries, nil
                    end,
                },
                get = function(self, key)
                    return self.cache:get(key)
                end,
                check = function(self, key)
                    return self.cache:get(key)
                end,
                insert = function(self, key, value, size)
                    return self.cache:set(key, value, size)
                end,
                clear = function(self)
                    self.cache:clear()
                end,
            }

            return cache
        end,
    }
    
    -- Mock Widgets
    package.loaded["ui/widget/container/centercontainer"] = mock_widget("CenterContainer")
    package.loaded["ui/widget/container/framecontainer"] = mock_widget("FrameContainer")
    package.loaded["ui/widget/container/inputcontainer"] = mock_widget("InputContainer")
    package.loaded["ui/widget/container/leftcontainer"] = mock_widget("LeftContainer")
    package.loaded["ui/widget/container/rightcontainer"] = mock_widget("RightContainer")
    package.loaded["ui/widget/container/topcontainer"] = mock_widget("TopContainer")
    package.loaded["ui/widget/container/bottomcontainer"] = mock_widget("BottomContainer")
    package.loaded["ui/widget/container/underlinecontainer"] = mock_widget("UnderlineContainer")
    package.loaded["ui/widget/container/alphacontainer"] = mock_widget("AlphaContainer")
    package.loaded["ui/widget/container/widgetcontainer"] = mock_widget("WidgetContainer")
    
    package.loaded["ui/widget/horizontalgroup"] = mock_widget("HorizontalGroup")
    package.loaded["ui/widget/horizontalspan"] = mock_widget("HorizontalSpan")
    package.loaded["ui/widget/verticalgroup"] = mock_widget("VerticalGroup")
    package.loaded["ui/widget/verticalspan"] = mock_widget("VerticalSpan")

    local OverlapGroup = mock_widget("OverlapGroup")
    OverlapGroup.init = function(self) end  -- Add empty init method
    package.loaded["ui/widget/overlapgroup"] = OverlapGroup
    
    package.loaded["ui/widget/imagewidget"] = mock_widget("ImageWidget")
    package.loaded["ui/widget/linewidget"] = mock_widget("LineWidget")
    package.loaded["ui/widget/textboxwidget"] = mock_widget("TextBoxWidget")
    package.loaded["ui/widget/textwidget"] = mock_widget("TextWidget")
    
    local ProgressWidget = mock_widget("ProgressWidget")
    ProgressWidget.setPercentage = function(self, val) self.percentage = val end
    package.loaded["ui/widget/progresswidget"] = ProgressWidget
    
    package.loaded["ui/widget/menu"] = {
        getMenuText = function(entry) return entry.text or "" end,
        getItemFontSize = function() return 20 end
    }
    
    package.loaded["ui/geometry"] = {
        new = function(self, o) 
            o = o or {}
            o.copy = function(self) 
                return { w = self.w, h = self.h, copy = self.copy } 
            end
            return o 
        end
    }
    
    package.loaded["ui/gesturerange"] = {
        new = function(self, o) return o end
    }
    
    package.loaded["optmath"] = {
        round = function(num) return math.floor(num + 0.5) end
    }

    package.loaded["ui/font"] = {
        getFace = function() return {} end
    }
    
    package.loaded["device"] = {
        screen = {
            scaleBySize = function(self, s) return s end,
            getWidth = function() return 600 end,
            getHeight = function() return 800 end
        },
        isTouchDevice = function() return true end,
        hasBattery = function() return false end,
        hasAuxBattery = function() return false end,
        hasFrontlight = function() return false end,
        hasNaturalLight = function() return false end,
        hasFastWifiStatusQuery = function() return true end,
        isCervantes = function() return false end,
        isKobo = function() return false end,
        getPowerDevice = function()
            return {
                getCapacity = function() return 100 end,
                getBatterySymbol = function() return "=" end,
                isCharged = function() return false end,
                isCharging = function() return false end,
                isAuxBatteryConnected = function() return false end,
                getAuxCapacity = function() return 100 end,
                isAuxCharged = function() return false end,
                isAuxCharging = function() return false end,
                isFrontlightOn = function() return false end,
                frontlightIntensity = function() return 0 end,
                frontlightWarmth = function() return 0 end,
            }
        end,
    }

    package.loaded["datetime"] = {
        secondsToHour = function() return "12:00" end,
    }

    package.loaded["ui/network/manager"] = {
        isWifiOn = function() return false end,
    }
    
    package.loaded["docsettings"] = {
        hasSidecarFile = function() return false end
    }

    package.loaded["document/documentregistry"] = {
        hasProvider = function() return true end,
        isImageFile = function() return false end,
        getProvider = function() return {} end,
        openDocument = function() return nil end,
    }

    package.loaded["ui/widget/booklist"] = {
        getBookInfo = function()
            return { been_opened = false }
        end,
        getBookStatus = function()
            return "new"
        end,
        getBookStatusString = function(status)
            local statuses = {
                all = "All",
                new = "New",
                reading = "Reading",
                abandoned = "On hold",
                complete = "Finished",
            }
            return statuses[status]
        end,
    }
    
    package.loaded["optmath"] = {
        round = function(n) return math.floor(n + 0.5) end
    }
    
    package.loaded["apps/filemanager/filemanagerutil"] = {
        splitFileNameType = function(f) return f, "epub" end,
        getDefaultDir = function() return "/default" end,
    }

    package.loaded["apps/filemanager/filemanagershortcuts"] = {
        hasFolderShortcut = function() return false end,
    }
    
    package.loaded["logger"] = {
        err = function() end,
        warn = function() end,
        info = function() end,
        dbg = function() end
    }
    
    package.loaded["util"] = {
        splitFilePathName = function(p) return "/dir", "file.epub" end,
        getFriendlySize = function() return "1MB" end,
        fileExists = function(filepath)
            -- Return true for font files needed by installFonts()
            if filepath:match("SourceSans3%-Regular%.ttf$") then return true end
            if filepath:match("SourceSerif4%-Regular%.ttf$") then return true end
            if filepath:match("SourceSerif4%-BoldIt%.ttf$") then return true end
            -- Return true for icon files needed by installIcons()
            if filepath:match("icons/.*%.svg$") then return true end
            -- Return true for version skip file
            if filepath:match("pt%-skipversioncheck%.txt$") then return false end
            return false
        end,
        directoryExists = function(path)
            if not path then return false end
            -- Return true for fonts and icons directories
            if path:match("/fonts$") or path:match("/icons$") then return true end
            return false
        end,
        makePath = function(path) return true end,
        splitToArray = function(str, sep)
            if not str or str == "" then return {} end
            local result = {}
            for match in (str..sep):gmatch("(.-)"..sep) do
                table.insert(result, match)
            end
            return result
        end,
        lastIndexOf = function(str, pattern)
            local last_pos = nil
            local start_pos = 1
            while true do
                local pos = string.find(str, pattern, start_pos, true)
                if not pos then break end
                last_pos = pos
                start_pos = pos + 1
            end
            return last_pos or 0
        end
    }

    -- Mock lfs (libkoreader-lfs)
    package.loaded["libs/libkoreader-lfs"] = {
        attributes = function(filepath, attr)
            if attr == "mode" then
                return nil
            end
            return nil
        end,
        dir = function(path)
            return function() return nil end
        end
    }

    package.loaded["l10n.gettext"] = setmetatable({
        ngettext = function(s) return s end
    }, {
        __call = function(_, s) return s end
    })
    
    package.loaded["ptdbg"] = {
        new = function() return { report = function() end } end,
        logprefix = "PTDBG"
    }
    
    -- Mock BookInfoManager
    local mock_bookinfo_settings = {}
    package.loaded["bookinfomanager"] = {
        _settings = mock_bookinfo_settings,
        BATCH_MISS = {
            _batch_miss = true,
        },
        getBookInfo = function() return nil end,
        getFolderCoverCandidateFilepaths = function() return nil end,
        getSetting = function(_, key)
            return mock_bookinfo_settings[key]
        end,
        saveSetting = function(_, key, value)
            if value == true then value = "Y" end
            if value == false then value = nil end
            mock_bookinfo_settings[key] = value
        end,
        toggleSetting = function(_, key)
            local current = mock_bookinfo_settings[key]
            local new_val = not current
            if new_val == true then 
                mock_bookinfo_settings[key] = "Y" 
            else 
                mock_bookinfo_settings[key] = nil 
            end
            return new_val
        end,
        getCachedCoverSize = function()
            return 100, 100, 1
        end,
        -- Cover cache methods
        getCachedCover = function() return nil end,
        isCoverCached = function() return false end,
        isBatchMiss = function(_, bookinfo)
            return bookinfo ~= nil and bookinfo._batch_miss == true
        end,
        cacheCover = function() end,
        clearCoverCache = function() end,
        invalidateCachedCover = function() end
    }
    
    -- Mock ptutil
    package.loaded["ptutil"] = {
        koreader_dir = "/tmp/koreader",
        installFonts = function() return true end,
        installIcons = function() return true end,
        getPluginDir = function() return "/plugin/dir" end,
        list_defaults = {
            fontsize_dec_step = 2,
            wright_font_nominal = 11,
            wright_font_max = 16,
            title_font_nominal = 20,
            title_font_max = 26,
            directory_font_nominal = 20,
            directory_font_max = 26,
            authors_font_nominal = 14,
            authors_font_max = 18,
            progress_bar_max_size = 235,
            progress_bar_pages_per_pixel = 3,
            progress_bar_min_size = 25,
        },
        grid_defaults = {
            progress_bar_max_size = 235,
            progress_bar_pages_per_pixel = 3,
            progress_bar_min_size = 40,
            fontsize_dec_step = 1,
            dir_font_nominal = 22,
            dir_font_min = 18,
            max_cols = 4,
            max_rows = 4,
            min_cols = 2,
            min_rows = 2,
            default_cols = 3,
            default_rows = 3,
        },
        footer_defaults = {
            font_size = 20,
        },
        bookstatus_defaults = {
            header_font_size = 20,
        },
        good_sans = "sans",
        good_serif = "serif",
        title_serif = "title_serif",
        good_serif_it = "serif_it",
        isPathChooser = function() return false end,
        getFolderCover = function() return nil end,
        getSubfolderCoverImages = function() return nil end,
        formatAuthors = function(a) return a end,
        showProgressBar = function(pages, render_context) return pages or 100, true end,
        onFocus = function(container, render_context) end,
        onUnfocus = function(container, render_context) end,
        mediumBlackLine = function() return {} end,
        thinGrayLine = function() return {} end,
        thinWhiteLine = function() return {} end,
        -- Font fallback function (for Issue #146 fix)
        getFontFace = function(font_name, size)
            return { size = size, name = font_name }
        end,
        -- Font size estimation cache functions
        clearFontSizeCache = function() end,
        -- Font sizing functions (Phase 3)
        estimateFontSize = function(params)
            return params.max_size or 26
        end,
        isTextQuickFit = function(params)
            return (#(params.text or "")) < 20
        end,
    }
    
    -- Mock G_reader_settings
    _G.G_reader_settings = {
        readSetting = function() return nil end,
        isTrue = function() return false end,
        nilOrTrue = function(_, _, default)
            if default ~= nil then
                return default
            end
            return true
        end,
    }

    -- Clear module caches to ensure fresh loads after mocks are set up
    package.loaded['ptutil'] = nil
    package.loaded['covermenu'] = nil
    package.loaded['listmenu'] = nil
    package.loaded['mosaicmenu'] = nil
    package.loaded['titlebar'] = nil
end

-- Helper to create a default render context for tests
-- This matches the structure from CoverMenu:buildRenderContext()
local function default_render_context()
    return {
        -- Display settings
        hide_file_info = nil,
        show_mosaic_titles = nil,
        progress_text_format = "status_and_percent",
        series_mode = nil,
        show_tags = nil,
        show_name_grid_folders = nil,
        -- Folder cover settings
        disable_auto_foldercovers = nil,
        use_stacked_foldercovers = nil,
        -- UI settings
        force_focus_indicator = nil,
        -- Progress bar settings (added in Phase 2)
        force_max_progressbars = nil,
        force_no_progressbars = nil,
        show_pages_read_as_progress = nil,
        -- Computed values
        is_pathchooser = false,
        is_touch_device = true,
    }
end

return setmetatable({
    default_render_context = default_render_context,
}, {
    __call = function(_, ...) return setup_mocks(...) end
})

local setup_mocks = require("spec.support.mock_ui")

local SAFE_VERSION = 202607000000

local function build_bookinfomanager()
    local settings = {}

    return {
        _settings = settings,
        getSetting = function(_, key)
            local value = settings[key]
            if value == nil or value == "Y" then
                return value
            end
            return tonumber(value) or value
        end,
        saveSetting = function(_, key, value)
            if value == true then
                value = "Y"
            elseif value == false or value == "" then
                value = nil
            end
            settings[key] = value
        end,
        toggleSetting = function(self, key)
            local new_value = self:getSetting(key) == nil
            self:saveSetting(key, new_value)
            return new_value
        end,
        closeDbConnection = function() end,
        deleteBookInfo = function() end,
        getBookInfo = function() return nil end,
        getDocProps = function() return nil end,
    }
end

local function load_main(opts)
    opts = opts or {}
    setup_mocks()

    local state = {
        shown_messages = {},
        plugins_disabled = opts.plugins_disabled or { coverbrowser = true },
        initial_setup_done = opts.initial_setup_done == true,
        skip_version_file = opts.skip_version_file == true,
        current_version = opts.current_version or SAFE_VERSION,
        restarted = 0,
        made_true = {},
    }

    local ffiutil = package.loaded["ffi/util"] or {}
    ffiutil.sleep = function() end
    package.loaded["ffi/util"] = ffiutil

    package.loaded["ui/uimanager"] = {
        show = function(_, widget)
            state.shown_messages[#state.shown_messages + 1] = widget
        end,
        nextTick = function(self, callback)
            if type(self) == "function" then
                callback = self
            end
            if callback then
                callback()
            end
        end,
        close = function() end,
        restartKOReader = function()
            state.restarted = state.restarted + 1
        end,
    }
    package.loaded["ui/widget/infomessage"] = {
        new = function(_, o) return o end,
    }
    package.loaded["version"] = {
        getNormalizedCurrentVersion = function()
            return state.current_version, "commit"
        end,
    }

    local util = package.loaded["util"] or {}
    util.arrayContains = function(values, expected)
        for _, value in ipairs(values or {}) do
            if value == expected then return true end
        end
        return false
    end
    util.fileExists = function(filepath)
        if filepath:match("pt%-skipversioncheck%.txt$") then
            return state.skip_version_file
        end
        return false
    end
    package.loaded["util"] = util

    package.loaded["ptutil"] = {
        koreader_dir = "/tmp/koreader",
        installFonts = function()
            return opts.fonts_available ~= false
        end,
        installIcons = function()
            return opts.icons_available ~= false
        end,
        getPluginDir = function() return "/plugin/dir" end,
        list_defaults = { default_rows = 3 },
        grid_defaults = { default_cols = 3, default_rows = 3 },
        footer_defaults = { font_size = 20, font_size_deviceinfo = 18 },
        bookstatus_defaults = { header_font_size = 20 },
    }

    local BookInfoManager = build_bookinfomanager()
    package.loaded["bookinfomanager"] = BookInfoManager

    package.loaded["ui/widget/bookstatuswidget"] = {}
    package.loaded["altbookstatuswidget"] = {
        genHeader = function() end,
        getStatusContent = function() end,
    }
    package.loaded["ui/widget/filechooser"] = {
        _recalculateDimen = function() end,
        updateItems = function() end,
        onCloseWidget = function() end,
        genItemTable = function() end,
    }
    package.loaded["ui/widget/pathchooser"] = {
        init = function() end,
    }
    package.loaded["apps/filemanager/filemanager"] = {
        setupLayout = function() end,
    }
    package.loaded["apps/filemanager/filemanagerhistory"] = {
        updateItemTable = function() end,
    }
    package.loaded["apps/filemanager/filemanagercollection"] = {
        updateItemTable = function() end,
    }
    package.loaded["apps/filemanager/filemanagerfilesearcher"] = {
        updateItemTable = function() end,
    }
    package.loaded["ui/widget/menu"] = {
        init = function() end,
        updatePageInfo = function() end,
    }
    package.loaded["dispatcher"] = {
        registerAction = function() end,
    }
    package.loaded["ui/trapper"] = {}
    package.loaded["ui/widget/booklist"] = package.loaded["ui/widget/booklist"] or {}

    _G.G_reader_settings = {
        readSetting = function(_, key)
            if key == "plugins_disabled" then
                return state.plugins_disabled
            end
            return nil
        end,
        isTrue = function(_, key)
            if key == "aaaProjectTitle_initial_default_setup_done2" then
                return state.initial_setup_done
            end
            return false
        end,
        makeTrue = function(_, key)
            state.made_true[key] = true
            if key == "aaaProjectTitle_initial_default_setup_done2" then
                state.initial_setup_done = true
            end
        end,
        saveSetting = function() end,
    }

    package.loaded["main"] = nil
    local main = require("main")
    return main, state, BookInfoManager
end

return {
    SAFE_VERSION = SAFE_VERSION,
    load_main = load_main,
}

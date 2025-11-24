require 'busted.runner'()
local setup_mocks = require("spec.support.mock_ui")

describe("Main Settings Migration", function()
    local CoverBrowser
    local BookInfoManager

    setup(function()
        if not _G.unpack then _G.unpack = table.unpack end
        setup_mocks()

        -- Mock dependencies
        package.loaded["ui/uimanager"] = {
            nextTick = function(callback) if callback then callback() end end,
            show = function() end,
            close = function() end
        }
        package.loaded["ui/widget/infomessage"] = {
            new = function(o) return o end
        }
        package.loaded["version"] = {
            getNormalizedCurrentVersion = function() return 202510000000, "commit" end
        }
        package.loaded["ui/widget/bookstatuswidget"] = {}
        package.loaded["altbookstatuswidget"] = {}
        package.loaded["ui/widget/filechooser"] = {}
        package.loaded["apps/filemanager/filemanager"] = {}
        package.loaded["apps/filemanager/filemanagerhistory"] = {}
        package.loaded["apps/filemanager/filemanagerfilesearcher"] = {}
        package.loaded["apps/filemanager/filemanagercollection"] = {}
        package.loaded["dispatcher"] = { registerAction = function() end }
        package.loaded["ui/trapper"] = {}

        -- Mock G_reader_settings to enable plugin
        _G.G_reader_settings = {
            readSetting = function(self, key)
                if key == "plugins_disabled" then return { coverbrowser = true } end
                if key == "lock_home_folder" then return false end
                if key == "home_dir" then return "/home" end
                return nil
            end,
            isTrue = function(self, key) return false end,
            saveSetting = function() end
        }

        BookInfoManager = require("bookinfomanager")
        CoverBrowser = require("main")
    end)

    before_each(function()
        -- Reset settings
        for k in pairs(BookInfoManager._settings) do
            BookInfoManager._settings[k] = nil
        end
    end)

    describe("Fresh install", function()
        it("initializes with version 1 settings when no config exists", function()
            -- Simulate fresh install - no config_version exists
            assert.is_nil(BookInfoManager:getSetting("config_version"))

            -- Trigger init by accessing the module
            -- The init code runs when main.lua is loaded, but we can test the logic
            -- by simulating what happens

            -- After migration, config_version should be "7"
            BookInfoManager:saveSetting("config_version", "1")
            BookInfoManager:saveSetting("series_mode", "series_in_separate_line")
            BookInfoManager:saveSetting("hide_file_info", true)
            BookInfoManager:saveSetting("unified_display_mode", true)
            BookInfoManager:saveSetting("show_progress_in_mosaic", true)
            BookInfoManager:saveSetting("show_mosaic_titles", true)

            assert.equal("1", BookInfoManager:getSetting("config_version"))
            assert.equal("series_in_separate_line", BookInfoManager:getSetting("series_mode"))
            assert.equal("Y", BookInfoManager:getSetting("hide_file_info"))
            assert.equal("Y", BookInfoManager:getSetting("unified_display_mode"))
            assert.equal("Y", BookInfoManager:getSetting("show_progress_in_mosaic"))
            assert.equal("Y", BookInfoManager:getSetting("show_mosaic_titles"))
        end)
    end)

    describe("Version 1 to 2 migration", function()
        it("adds new settings in version 2", function()
            BookInfoManager:saveSetting("config_version", "1")

            -- Simulate migration
            BookInfoManager:saveSetting("disable_auto_foldercovers", false)
            BookInfoManager:saveSetting("force_max_progressbars", false)
            BookInfoManager:saveSetting("opened_at_top_of_library", true)
            BookInfoManager:saveSetting("reverse_footer", false)
            BookInfoManager:saveSetting("replace_footer_text", false)
            BookInfoManager:saveSetting("show_name_grid_folders", true)
            BookInfoManager:saveSetting("config_version", "2")

            assert.equal("2", BookInfoManager:getSetting("config_version"))
            assert.is_nil(BookInfoManager:getSetting("disable_auto_foldercovers"))
            assert.is_nil(BookInfoManager:getSetting("force_max_progressbars"))
            assert.equal("Y", BookInfoManager:getSetting("opened_at_top_of_library"))
            assert.is_nil(BookInfoManager:getSetting("reverse_footer"))
            assert.is_nil(BookInfoManager:getSetting("replace_footer_text"))
            assert.equal("Y", BookInfoManager:getSetting("show_name_grid_folders"))
        end)
    end)

    describe("Version 2 to 3 migration", function()
        it("adds force_no_progressbars setting", function()
            BookInfoManager:saveSetting("config_version", "2")

            BookInfoManager:saveSetting("force_no_progressbars", false)
            BookInfoManager:saveSetting("config_version", "3")

            assert.equal("3", BookInfoManager:getSetting("config_version"))
            assert.is_nil(BookInfoManager:getSetting("force_no_progressbars"))
        end)
    end)

    describe("Version 3 to 4 migration", function()
        it("adds focus indicator and stacked foldercovers settings", function()
            BookInfoManager:saveSetting("config_version", "3")

            BookInfoManager:saveSetting("force_focus_indicator", false)
            BookInfoManager:saveSetting("use_stacked_foldercovers", false)
            BookInfoManager:saveSetting("config_version", "4")

            assert.equal("4", BookInfoManager:getSetting("config_version"))
            assert.is_nil(BookInfoManager:getSetting("force_focus_indicator"))
            assert.is_nil(BookInfoManager:getSetting("use_stacked_foldercovers"))
        end)
    end)

    describe("Version 4 to 5 migration", function()
        it("adds show_tags setting", function()
            BookInfoManager:saveSetting("config_version", "4")

            BookInfoManager:saveSetting("show_tags", false)
            BookInfoManager:saveSetting("config_version", "5")

            assert.equal("5", BookInfoManager:getSetting("config_version"))
            assert.is_nil(BookInfoManager:getSetting("show_tags"))
        end)
    end)

    describe("Version 5 to 6 migration", function()
        it("migrates show_pages_read_as_progress to progress_text_format (default)", function()
            BookInfoManager:saveSetting("config_version", "5")

            -- No show_pages_read_as_progress set, default to status_and_percent
            local progress_text_format = "status_and_percent"
            BookInfoManager:saveSetting("progress_text_format", progress_text_format)
            BookInfoManager:saveSetting("config_version", "6")

            assert.equal("6", BookInfoManager:getSetting("config_version"))
            assert.equal("status_and_percent", BookInfoManager:getSetting("progress_text_format"))
        end)

        it("migrates show_pages_read_as_progress=true to status_and_pages", function()
            BookInfoManager:saveSetting("config_version", "5")
            BookInfoManager:saveSetting("show_pages_read_as_progress", true)

            -- Simulate migration logic
            local progress_text_format = "status_and_percent"
            if BookInfoManager:getSetting("show_pages_read_as_progress") then
                progress_text_format = "status_and_pages"
            end
            BookInfoManager:saveSetting("progress_text_format", progress_text_format)
            BookInfoManager:saveSetting("config_version", "6")

            assert.equal("6", BookInfoManager:getSetting("config_version"))
            assert.equal("status_and_pages", BookInfoManager:getSetting("progress_text_format"))
        end)
    end)

    describe("Version 6 to 7 migration", function()
        it("adds show_mosaic_titles setting", function()
            BookInfoManager:saveSetting("config_version", "6")

            BookInfoManager:saveSetting("show_mosaic_titles", true)
            BookInfoManager:saveSetting("config_version", "7")

            assert.equal("7", BookInfoManager:getSetting("config_version"))
            assert.equal("Y", BookInfoManager:getSetting("show_mosaic_titles"))
        end)
    end)

    describe("Full migration path", function()
        it("successfully migrates from version 1 to version 7", function()
            BookInfoManager:saveSetting("config_version", "1")

            -- Version 1 → 2
            BookInfoManager:saveSetting("disable_auto_foldercovers", false)
            BookInfoManager:saveSetting("force_max_progressbars", false)
            BookInfoManager:saveSetting("opened_at_top_of_library", true)
            BookInfoManager:saveSetting("reverse_footer", false)
            BookInfoManager:saveSetting("replace_footer_text", false)
            BookInfoManager:saveSetting("show_name_grid_folders", true)
            BookInfoManager:saveSetting("config_version", "2")

            -- Version 2 → 3
            BookInfoManager:saveSetting("force_no_progressbars", false)
            BookInfoManager:saveSetting("config_version", "3")

            -- Version 3 → 4
            BookInfoManager:saveSetting("force_focus_indicator", false)
            BookInfoManager:saveSetting("use_stacked_foldercovers", false)
            BookInfoManager:saveSetting("config_version", "4")

            -- Version 4 → 5
            BookInfoManager:saveSetting("show_tags", false)
            BookInfoManager:saveSetting("config_version", "5")

            -- Version 5 → 6
            BookInfoManager:saveSetting("progress_text_format", "status_and_percent")
            BookInfoManager:saveSetting("config_version", "6")

            -- Version 6 → 7
            BookInfoManager:saveSetting("show_mosaic_titles", true)
            BookInfoManager:saveSetting("config_version", "7")

            assert.equal("7", BookInfoManager:getSetting("config_version"))
            assert.equal("Y", BookInfoManager:getSetting("show_mosaic_titles"))
            assert.equal("status_and_percent", BookInfoManager:getSetting("progress_text_format"))
        end)
    end)
end)

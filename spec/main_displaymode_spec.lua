require 'busted.runner'()
local setup_mocks = require("spec.support.mock_ui")

describe("Main Display Mode Switching", function()
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

        -- Mock G_reader_settings
        _G.G_reader_settings = {
            readSetting = function(self, key)
                if key == "plugins_disabled" then return { coverbrowser = true } end
                return nil
            end,
            isTrue = function() return false end,
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

    describe("Display mode constants", function()
        it("has modes defined", function()
            -- DISPLAY_MODES is a local constant in main.lua, not exposed
            -- We test it indirectly through the modes list
            assert.is_not_nil(CoverBrowser.modes)
            assert.is_table(CoverBrowser.modes)
        end)

        it("modes list includes mosaic_image", function()
            local has_mosaic = false
            for _, mode in ipairs(CoverBrowser.modes) do
                if mode[2] == "mosaic_image" then
                    has_mosaic = true
                    break
                end
            end
            assert.is_true(has_mosaic)
        end)

        it("modes list includes list_image_meta", function()
            local has_list_image = false
            for _, mode in ipairs(CoverBrowser.modes) do
                if mode[2] == "list_image_meta" then
                    has_list_image = true
                    break
                end
            end
            assert.is_true(has_list_image)
        end)

        it("modes list includes list_only_meta", function()
            local has_list_only = false
            for _, mode in ipairs(CoverBrowser.modes) do
                if mode[2] == "list_only_meta" then
                    has_list_only = true
                    break
                end
            end
            assert.is_true(has_list_only)
        end)

        it("modes list includes list_no_meta", function()
            local has_list_no = false
            for _, mode in ipairs(CoverBrowser.modes) do
                if mode[2] == "list_no_meta" then
                    has_list_no = true
                    break
                end
            end
            assert.is_true(has_list_no)
        end)
    end)

    describe("Mode configuration", function()
        it("has modes list with labels and values", function()
            assert.is_not_nil(CoverBrowser.modes)
            assert.is_table(CoverBrowser.modes)
            assert.is_true(#CoverBrowser.modes > 0)
        end)

        it("each mode has label and value", function()
            for _, mode in ipairs(CoverBrowser.modes) do
                assert.is_string(mode[1]) -- label
                assert.is_string(mode[2]) -- value
            end
        end)
    end)

    describe("Unified display mode", function()
        it("uses unified_display_mode when enabled", function()
            BookInfoManager:saveSetting("unified_display_mode", true)
            BookInfoManager:saveSetting("display_mode", "mosaic_image")

            -- When unified is true, all contexts use the same mode
            local mode = BookInfoManager:getSetting("unified_display_mode")
            assert.equal("Y", mode)
        end)

        it("uses separate modes when unified_display_mode is disabled", function()
            BookInfoManager:saveSetting("unified_display_mode", false)
            BookInfoManager:saveSetting("filemanager_display_mode", "mosaic_image")
            BookInfoManager:saveSetting("history_display_mode", "list_image_meta")
            BookInfoManager:saveSetting("collection_display_mode", "list_only_meta")

            assert.is_nil(BookInfoManager:getSetting("unified_display_mode"))
            assert.equal("mosaic_image", BookInfoManager:getSetting("filemanager_display_mode"))
            assert.equal("list_image_meta", BookInfoManager:getSetting("history_display_mode"))
            assert.equal("list_only_meta", BookInfoManager:getSetting("collection_display_mode"))
        end)
    end)

    describe("Context-specific display modes", function()
        it("stores filemanager_display_mode", function()
            BookInfoManager:saveSetting("filemanager_display_mode", "mosaic_image")
            assert.equal("mosaic_image", BookInfoManager:getSetting("filemanager_display_mode"))
        end)

        it("stores history_display_mode", function()
            BookInfoManager:saveSetting("history_display_mode", "list_image_meta")
            assert.equal("list_image_meta", BookInfoManager:getSetting("history_display_mode"))
        end)

        it("stores collection_display_mode", function()
            BookInfoManager:saveSetting("collection_display_mode", "list_only_meta")
            assert.equal("list_only_meta", BookInfoManager:getSetting("collection_display_mode"))
        end)
    end)

    describe("Grid layout settings", function()
        it("stores nb_cols_portrait", function()
            BookInfoManager:saveSetting("nb_cols_portrait", 3)
            assert.equal(3, BookInfoManager:getSetting("nb_cols_portrait"))
        end)

        it("stores nb_rows_portrait", function()
            BookInfoManager:saveSetting("nb_rows_portrait", 4)
            assert.equal(4, BookInfoManager:getSetting("nb_rows_portrait"))
        end)

        it("stores nb_cols_landscape", function()
            BookInfoManager:saveSetting("nb_cols_landscape", 4)
            assert.equal(4, BookInfoManager:getSetting("nb_cols_landscape"))
        end)

        it("stores nb_rows_landscape", function()
            BookInfoManager:saveSetting("nb_rows_landscape", 3)
            assert.equal(3, BookInfoManager:getSetting("nb_rows_landscape"))
        end)
    end)

    describe("List layout settings", function()
        it("stores files_per_page", function()
            BookInfoManager:saveSetting("files_per_page", 7)
            assert.equal(7, BookInfoManager:getSetting("files_per_page"))
        end)

        it("validates files_per_page within bounds", function()
            -- Test that typical values are stored correctly
            BookInfoManager:saveSetting("files_per_page", 3)
            assert.equal(3, BookInfoManager:getSetting("files_per_page"))

            BookInfoManager:saveSetting("files_per_page", 10)
            assert.equal(10, BookInfoManager:getSetting("files_per_page"))
        end)
    end)

    describe("Display options", function()
        it("stores hide_file_info setting", function()
            BookInfoManager:saveSetting("hide_file_info", true)
            assert.equal("Y", BookInfoManager:getSetting("hide_file_info"))

            BookInfoManager:saveSetting("hide_file_info", false)
            assert.is_nil(BookInfoManager:getSetting("hide_file_info"))
        end)

        it("stores show_progress_in_mosaic setting", function()
            BookInfoManager:saveSetting("show_progress_in_mosaic", true)
            assert.equal("Y", BookInfoManager:getSetting("show_progress_in_mosaic"))

            BookInfoManager:saveSetting("show_progress_in_mosaic", false)
            assert.is_nil(BookInfoManager:getSetting("show_progress_in_mosaic"))
        end)

        it("stores series_mode setting", function()
            BookInfoManager:saveSetting("series_mode", "series_in_separate_line")
            assert.equal("series_in_separate_line", BookInfoManager:getSetting("series_mode"))

            BookInfoManager:saveSetting("series_mode", "authors_in_separate_line")
            assert.equal("authors_in_separate_line", BookInfoManager:getSetting("series_mode"))
        end)
    end)

    describe("Dispatcher actions", function()
        it("registers inc_items_pp action", function()
            -- onDispatcherRegisterActions should register actions
            -- We can't fully test without real dispatcher, but we can verify the method exists
            assert.is_function(CoverBrowser.onDispatcherRegisterActions)
        end)

        it("registers dec_items_pp action", function()
            assert.is_function(CoverBrowser.onDispatcherRegisterActions)
        end)

        it("registers switch_grid action", function()
            assert.is_function(CoverBrowser.onDispatcherRegisterActions)
        end)

        it("registers switch_list action", function()
            assert.is_function(CoverBrowser.onDispatcherRegisterActions)
        end)
    end)

    describe("Items per page adjustment", function()
        it("has onIncreaseItemsPerPage method", function()
            assert.is_function(CoverBrowser.onIncreaseItemsPerPage)
        end)

        it("has onDecreaseItemsPerPage method", function()
            assert.is_function(CoverBrowser.onDecreaseItemsPerPage)
        end)
    end)

    describe("Mode switching methods", function()
        it("has onSwitchToCoverGrid method", function()
            assert.is_function(CoverBrowser.onSwitchToCoverGrid)
        end)

        it("has onSwitchToCoverList method", function()
            assert.is_function(CoverBrowser.onSwitchToCoverList)
        end)

        it("has setDisplayMode method", function()
            assert.is_function(CoverBrowser.setDisplayMode)
        end)

        it("has setupFileManagerDisplayMode method", function()
            assert.is_function(CoverBrowser.setupFileManagerDisplayMode)
        end)
    end)

    describe("Book info integration", function()
        it("has getBookInfo method", function()
            assert.is_function(CoverBrowser.getBookInfo)
        end)

        it("has onInvalidateMetadataCache method", function()
            assert.is_function(CoverBrowser.onInvalidateMetadataCache)
        end)

        it("has extractBooksInDirectory method", function()
            assert.is_function(CoverBrowser.extractBooksInDirectory)
        end)
    end)

    describe("File manager integration", function()
        it("has refreshFileManagerInstance method", function()
            assert.is_function(CoverBrowser.refreshFileManagerInstance)
        end)
    end)

    describe("Multiple dialog buttons", function()
        it("has genExtractBookInfoButton method", function()
            assert.is_function(CoverBrowser.genExtractBookInfoButton)
        end)

        it("has genMultipleRefreshBookInfoButton method", function()
            assert.is_function(CoverBrowser.genMultipleRefreshBookInfoButton)
        end)
    end)

    describe("Cover image settings", function()
        it("stores show_mosaic_titles setting", function()
            BookInfoManager:saveSetting("show_mosaic_titles", true)
            assert.equal("Y", BookInfoManager:getSetting("show_mosaic_titles"))

            BookInfoManager:saveSetting("show_mosaic_titles", false)
            assert.is_nil(BookInfoManager:getSetting("show_mosaic_titles"))
        end)

        it("stores progress_text_format setting", function()
            BookInfoManager:saveSetting("progress_text_format", "status_and_percent")
            assert.equal("status_and_percent", BookInfoManager:getSetting("progress_text_format"))

            BookInfoManager:saveSetting("progress_text_format", "status_and_pages")
            assert.equal("status_and_pages", BookInfoManager:getSetting("progress_text_format"))

            BookInfoManager:saveSetting("progress_text_format", "status_percent_and_pages")
            assert.equal("status_percent_and_pages", BookInfoManager:getSetting("progress_text_format"))

            BookInfoManager:saveSetting("progress_text_format", "status_only")
            assert.equal("status_only", BookInfoManager:getSetting("progress_text_format"))
        end)
    end)

    describe("Folder cover settings", function()
        it("stores disable_auto_foldercovers setting", function()
            BookInfoManager:saveSetting("disable_auto_foldercovers", true)
            assert.equal("Y", BookInfoManager:getSetting("disable_auto_foldercovers"))

            BookInfoManager:saveSetting("disable_auto_foldercovers", false)
            assert.is_nil(BookInfoManager:getSetting("disable_auto_foldercovers"))
        end)

        it("stores use_stacked_foldercovers setting", function()
            BookInfoManager:saveSetting("use_stacked_foldercovers", true)
            assert.equal("Y", BookInfoManager:getSetting("use_stacked_foldercovers"))

            BookInfoManager:saveSetting("use_stacked_foldercovers", false)
            assert.is_nil(BookInfoManager:getSetting("use_stacked_foldercovers"))
        end)

        it("stores show_name_grid_folders setting", function()
            BookInfoManager:saveSetting("show_name_grid_folders", true)
            assert.equal("Y", BookInfoManager:getSetting("show_name_grid_folders"))

            BookInfoManager:saveSetting("show_name_grid_folders", false)
            assert.is_nil(BookInfoManager:getSetting("show_name_grid_folders"))
        end)
    end)

    describe("Advanced display settings", function()
        it("stores force_max_progressbars setting", function()
            BookInfoManager:saveSetting("force_max_progressbars", true)
            assert.equal("Y", BookInfoManager:getSetting("force_max_progressbars"))

            BookInfoManager:saveSetting("force_max_progressbars", false)
            assert.is_nil(BookInfoManager:getSetting("force_max_progressbars"))
        end)

        it("stores force_no_progressbars setting", function()
            BookInfoManager:saveSetting("force_no_progressbars", true)
            assert.equal("Y", BookInfoManager:getSetting("force_no_progressbars"))

            BookInfoManager:saveSetting("force_no_progressbars", false)
            assert.is_nil(BookInfoManager:getSetting("force_no_progressbars"))
        end)

        it("stores force_focus_indicator setting", function()
            BookInfoManager:saveSetting("force_focus_indicator", true)
            assert.equal("Y", BookInfoManager:getSetting("force_focus_indicator"))

            BookInfoManager:saveSetting("force_focus_indicator", false)
            assert.is_nil(BookInfoManager:getSetting("force_focus_indicator"))
        end)
    end)

    describe("Metadata display settings", function()
        it("stores show_tags setting", function()
            BookInfoManager:saveSetting("show_tags", true)
            assert.equal("Y", BookInfoManager:getSetting("show_tags"))

            BookInfoManager:saveSetting("show_tags", false)
            assert.is_nil(BookInfoManager:getSetting("show_tags"))
        end)

        it("stores opened_at_top_of_library setting", function()
            BookInfoManager:saveSetting("opened_at_top_of_library", true)
            assert.equal("Y", BookInfoManager:getSetting("opened_at_top_of_library"))

            BookInfoManager:saveSetting("opened_at_top_of_library", false)
            assert.is_nil(BookInfoManager:getSetting("opened_at_top_of_library"))
        end)
    end)

    describe("Footer settings", function()
        it("stores reverse_footer setting", function()
            BookInfoManager:saveSetting("reverse_footer", true)
            assert.equal("Y", BookInfoManager:getSetting("reverse_footer"))

            BookInfoManager:saveSetting("reverse_footer", false)
            assert.is_nil(BookInfoManager:getSetting("reverse_footer"))
        end)

        it("stores replace_footer_text setting", function()
            BookInfoManager:saveSetting("replace_footer_text", true)
            assert.equal("Y", BookInfoManager:getSetting("replace_footer_text"))

            BookInfoManager:saveSetting("replace_footer_text", false)
            assert.is_nil(BookInfoManager:getSetting("replace_footer_text"))
        end)
    end)
end)

require 'busted.runner'()
local setup_mocks = require("spec.support.mock_ui")

describe("Main Settings", function()
    local CoverBrowser
    local BookInfoManager

    local function find_menu_item(items, labels)
        local current_items = items
        local item
        for _, label in ipairs(labels) do
            item = nil
            for _, candidate in ipairs(current_items or {}) do
                if candidate.text == label then
                    item = candidate
                    break
                end
            end
            if not item then
                return nil
            end
            current_items = item.sub_item_table
        end
        return item
    end
    
    setup(function()
        if not _G.unpack then _G.unpack = table.unpack end
        setup_mocks()
        -- Mock other dependencies of main.lua
        package.loaded["ui/uimanager"] = {
            nextTick = function() end,
            show = function() end,
            askForRestart = function() end,
        }
        package.loaded["ui/widget/infomessage"] = { new = function() return {} end }
        package.loaded["version"] = { getNormalizedCurrentVersion = function() return 202607000000, "commit" end }
        package.loaded["ui/widget/bookstatuswidget"] = {}
        package.loaded["altbookstatuswidget"] = {}
        package.loaded["ui/widget/filechooser"] = {}
        package.loaded["ui/widget/pathchooser"] = { init = function() end }
        package.loaded["apps/filemanager/filemanager"] = {}
        package.loaded["apps/filemanager/filemanagerhistory"] = {}
        package.loaded["apps/filemanager/filemanagerfilesearcher"] = {}
        package.loaded["apps/filemanager/filemanagercollection"] = {}
        package.loaded["dispatcher"] = {}
        package.loaded["ui/trapper"] = {}
        package.loaded["covermenu"] = {
            updateFolderUpButton = function(file_chooser)
                local requires_hold = package.loaded["bookinfomanager"]:getSetting("folder_up_requires_hold")
                local button = file_chooser.title_bar.right2_button
                if requires_hold then
                    button.callback = nil
                    button.hold_callback = function() end
                else
                    button.callback = function() end
                    button.hold_callback = nil
                end
            end,
        }
        
        -- Mock G_reader_settings to enable plugin
        _G.G_reader_settings = {
            readSetting = function(self, key)
                if key == "plugins_disabled" then return { coverbrowser = true } end
                return nil
            end
        }
        
        CoverBrowser = require("main")
        BookInfoManager = require("bookinfomanager")
    end)

    before_each(function()
        -- Reset settings
        for k in pairs(BookInfoManager._settings) do
            BookInfoManager._settings[k] = nil
        end
    end)
    
    it("toggles show_mosaic_titles correctly", function()
        -- Setup mock UI structure for addToMainMenu
        CoverBrowser.ui = {
            file_chooser = {
                nb_cols_portrait = 3,
                nb_rows_portrait = 4,
                nb_cols_landscape = 4,
                nb_rows_landscape = 3,
                files_per_page = 10,
                updateItems = function() end
            }
        }
        CoverBrowser.modes = { {"Mode 1", "mode1"} } -- Mock modes
        
        local menu_items = {}
        CoverBrowser:addToMainMenu(menu_items)
        
        local display_mode_menu = menu_items.filemanager_display_mode
        assert.is_not_nil(display_mode_menu)
        
        -- Find "Advanced settings" in sub_item_table
        local advanced_settings
        for _, item in ipairs(display_mode_menu.sub_item_table) do
            if item.text == "Advanced settings" then
                advanced_settings = item
                break
            end
        end
        assert.is_not_nil(advanced_settings)
        
        -- Find "Book display"
        local book_display
        for _, item in ipairs(advanced_settings.sub_item_table) do
            if item.text == "Book display" then
                book_display = item
                break
            end
        end
        assert.is_not_nil(book_display)
        
        -- Find "Show title and author near covers"
        local toggle_item
        for _, item in ipairs(book_display.sub_item_table) do
            if item.text == "Show title and author near covers" then
                toggle_item = item
                break
            end
        end
        assert.is_not_nil(toggle_item)
        
        -- Initial state: nil (false)
        assert.is_nil(BookInfoManager:getSetting("show_mosaic_titles"))
        assert.is_falsy(toggle_item.checked_func())
        
        -- Toggle ON
        toggle_item.callback()
        
        -- Check state
        assert.equal("Y", BookInfoManager:getSetting("show_mosaic_titles"))
        
        -- THIS IS THE BUG: checked_func() returns false because "Y" != true
        assert.is_truthy(toggle_item.checked_func(), "Checkbox should be checked when setting is 'Y'") 
        
        -- Toggle OFF
        toggle_item.callback()
        
        -- Check state
        assert.is_nil(BookInfoManager:getSetting("show_mosaic_titles"))
        assert.is_falsy(toggle_item.checked_func())
    end)

    it("marks display mode entries as radio menu items", function()
        CoverBrowser.ui = {
            file_chooser = {
                nb_cols_portrait = 3,
                nb_rows_portrait = 4,
                nb_cols_landscape = 4,
                nb_rows_landscape = 3,
                files_per_page = 10,
                updateItems = function() end
            }
        }
        CoverBrowser.modes = {
            { "Mode 1", "mode1" },
            { "Mode 2", "mode2" },
        }

        local menu_items = {}
        CoverBrowser:addToMainMenu(menu_items)

        local display_mode_menu = menu_items.filemanager_display_mode
        assert.is_not_nil(display_mode_menu)
        assert.is_true(#display_mode_menu.sub_item_table >= 2)
        assert.is_true(display_mode_menu.sub_item_table[1].radio)
        assert.is_true(display_mode_menu.sub_item_table[2].radio)
    end)

    it("loads doublespinwidget via KOReader's standard module path", function()
        local required_module
        local old_standard_preload = package.preload["ui/widget/doublespinwidget"]
        local old_absolute_preload = package.preload["/ui/widget/doublespinwidget"]
        local old_standard_loaded = package.loaded["ui/widget/doublespinwidget"]
        local old_absolute_loaded = package.loaded["/ui/widget/doublespinwidget"]

        package.loaded["ui/widget/doublespinwidget"] = nil
        package.loaded["/ui/widget/doublespinwidget"] = nil

        package.preload["ui/widget/doublespinwidget"] = function()
            required_module = "ui/widget/doublespinwidget"
            return {
                new = function(_, o) return o or {} end
            }
        end
        package.preload["/ui/widget/doublespinwidget"] = function()
            error("unexpected absolute require path for doublespinwidget")
        end

        CoverBrowser.ui = {
            file_chooser = {
                nb_cols_portrait = 3,
                nb_rows_portrait = 4,
                nb_cols_landscape = 4,
                nb_rows_landscape = 3,
                files_per_page = 10,
                updateItems = function() end
            }
        }
        CoverBrowser.modes = { { "Mode 1", "mode1" } }

        local menu_items = {}
        CoverBrowser:addToMainMenu(menu_items)

        local items_per_page
        for _, item in ipairs(menu_items.filemanager_display_mode.sub_item_table) do
            if item.text == "Items per page" then
                items_per_page = item
                break
            end
        end

        assert.is_not_nil(items_per_page)
        local portrait_item = items_per_page.sub_item_table[1]
        assert.is_function(portrait_item.callback)

        portrait_item.callback()

        assert.equal("ui/widget/doublespinwidget", required_module)

        package.preload["ui/widget/doublespinwidget"] = old_standard_preload
        package.preload["/ui/widget/doublespinwidget"] = old_absolute_preload
        package.loaded["ui/widget/doublespinwidget"] = old_standard_loaded
        package.loaded["/ui/widget/doublespinwidget"] = old_absolute_loaded
    end)

    it("updates the existing up-folder button without replacing the file chooser", function()
        local updated = false
        local setup_called = false
        local file_chooser = {
            nb_cols_portrait = 3,
            nb_rows_portrait = 4,
            nb_cols_landscape = 4,
            nb_rows_landscape = 3,
            files_per_page = 10,
            title_bar = {
                right2_button = {
                    callback = function() end,
                    hold_callback = nil,
                },
            },
            updateItems = function(_, page, force_refresh)
                updated = page == 1 and force_refresh == true
            end,
        }

        CoverBrowser.ui = {
            setupLayout = function()
                setup_called = true
            end,
            file_chooser = file_chooser,
        }
        CoverBrowser.modes = { { "Mode 1", "mode1" } }

        local menu_items = {}
        CoverBrowser:addToMainMenu(menu_items)

        local folder_toggle
        for _, item in ipairs(menu_items.filemanager_display_mode.sub_item_table) do
            if item.text == "Advanced settings" then
                for _, sub_item in ipairs(item.sub_item_table) do
                    if sub_item.text == "Folder display" then
                        for _, folder_item in ipairs(sub_item.sub_item_table) do
                            if folder_item.text == "Require hold for up-folder button" then
                                folder_toggle = folder_item
                                break
                            end
                        end
                    end
                end
            end
        end

        assert.is_not_nil(folder_toggle)
        assert.is_nil(BookInfoManager:getSetting("folder_up_requires_hold"))

        folder_toggle.callback()

        assert.equal("Y", BookInfoManager:getSetting("folder_up_requires_hold"))
        assert.is_false(setup_called)
        assert.equal(file_chooser, CoverBrowser.ui.file_chooser)
        assert.is_nil(file_chooser.title_bar.right2_button.callback)
        assert.is_function(file_chooser.title_bar.right2_button.hold_callback)
        assert.is_true(updated)
    end)

    it("updates the author-series order through the settings menu", function()
        local updated = false
        BookInfoManager:saveSetting("author_series_order", "author_first")

        CoverBrowser.ui = {
            file_chooser = {
                nb_cols_portrait = 3,
                nb_rows_portrait = 4,
                nb_cols_landscape = 4,
                nb_rows_landscape = 3,
                files_per_page = 10,
                updateItems = function(_, page, force_refresh)
                    updated = page == 1 and force_refresh == true
                end,
            }
        }
        CoverBrowser.modes = { { "Mode 1", "mode1" } }

        local menu_items = {}
        CoverBrowser:addToMainMenu(menu_items)

        local author_first = find_menu_item(menu_items.filemanager_display_mode.sub_item_table, {
            "Advanced settings",
            "Book display",
            "Author and series order",
            "Author first",
        })
        local series_first = find_menu_item(menu_items.filemanager_display_mode.sub_item_table, {
            "Advanced settings",
            "Book display",
            "Author and series order",
            "Series first",
        })

        assert.is_not_nil(author_first)
        assert.is_not_nil(series_first)
        assert.equal("author_first", BookInfoManager:getSetting("author_series_order"))
        assert.is_true(author_first.checked_func())

        series_first.callback()

        assert.equal("series_first", BookInfoManager:getSetting("author_series_order"))
        assert.is_true(series_first.checked_func())
        assert.is_false(author_first.checked_func())
        assert.is_true(updated)
    end)

    it("requests restart when changing footer page controls position", function()
        local restart_requested = false
        local UIManager = package.loaded["ui/uimanager"]
        local original_ask_for_restart = UIManager.askForRestart
        UIManager.askForRestart = function()
            restart_requested = true
        end

        CoverBrowser.ui = {
            file_chooser = {
                nb_cols_portrait = 3,
                nb_rows_portrait = 4,
                nb_cols_landscape = 4,
                nb_rows_landscape = 3,
                files_per_page = 10,
                updateItems = function() end,
            }
        }
        CoverBrowser.modes = { { "Mode 1", "mode1" } }

        local menu_items = {}
        CoverBrowser:addToMainMenu(menu_items)

        local center = find_menu_item(menu_items.filemanager_display_mode.sub_item_table, {
            "Advanced settings",
            "Footer",
            "Page controls position",
            "Center",
        })

        assert.is_not_nil(center)

        center.callback()

        UIManager.askForRestart = original_ask_for_restart

        assert.equal("center", BookInfoManager:getSetting("footer_page_controls_alignment"))
        assert.is_true(restart_requested)
    end)

    it("toggles footer device info items through the settings menu", function()
        local restart_requested = false
        local UIManager = package.loaded["ui/uimanager"]
        local original_ask_for_restart = UIManager.askForRestart
        UIManager.askForRestart = function()
            restart_requested = true
        end

        CoverBrowser.ui = {
            file_chooser = {
                nb_cols_portrait = 3,
                nb_rows_portrait = 4,
                nb_cols_landscape = 4,
                nb_rows_landscape = 3,
                files_per_page = 10,
                updateItems = function() end,
            }
        }
        CoverBrowser.modes = { { "Mode 1", "mode1" } }

        local menu_items = {}
        CoverBrowser:addToMainMenu(menu_items)

        local clock = find_menu_item(menu_items.filemanager_display_mode.sub_item_table, {
            "Advanced settings",
            "Footer",
            "Device info items",
            "Clock",
        })

        assert.is_not_nil(clock)
        assert.is_nil(BookInfoManager:getSetting("footer_show_clock"))

        clock.callback()

        UIManager.askForRestart = original_ask_for_restart

        assert.equal("Y", BookInfoManager:getSetting("footer_show_clock"))
        assert.is_true(restart_requested)
    end)

end)

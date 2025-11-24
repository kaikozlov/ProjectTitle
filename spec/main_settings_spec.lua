require 'busted.runner'()
local setup_mocks = require("spec.support.mock_ui")

describe("Main Settings", function()
    local CoverBrowser
    local BookInfoManager
    
    setup(function()
        if not _G.unpack then _G.unpack = table.unpack end
        setup_mocks()
        -- Mock other dependencies of main.lua
        package.loaded["ui/uimanager"] = { nextTick = function() end, show = function() end }
        package.loaded["ui/widget/infomessage"] = { new = function() return {} end }
        package.loaded["version"] = { getNormalizedCurrentVersion = function() return 202510000000, "commit" end }
        package.loaded["ui/widget/bookstatuswidget"] = {}
        package.loaded["altbookstatuswidget"] = {}
        package.loaded["ui/widget/filechooser"] = {}
        package.loaded["apps/filemanager/filemanager"] = {}
        package.loaded["apps/filemanager/filemanagerhistory"] = {}
        package.loaded["apps/filemanager/filemanagerfilesearcher"] = {}
        package.loaded["apps/filemanager/filemanagercollection"] = {}
        package.loaded["dispatcher"] = {}
        package.loaded["ui/trapper"] = {}
        
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
end)

require 'busted.runner'()
local mock_ui = require("spec.support.mock_ui")

describe("MosaicMenu Progress Indicators", function()
    local MosaicMenu
    local BookInfoManager
    local ptutil
    local DocSettings
    
    setup(function()
        mock_ui()
        
        -- Force reload of mosaicmenu to pick up mocked T
        package.loaded["mosaicmenu"] = nil
        
        -- Mock dependencies
        BookInfoManager = require("bookinfomanager")
        ptutil = require("ptutil")
        DocSettings = require("docsettings")
        
        -- Mock BookInfoManager methods
        BookInfoManager.getBookInfo = function() return { pages = nil } end -- Database pages nil
        BookInfoManager.getSetting = function() return nil end
        BookInfoManager.getCachedCoverSize = function() return 100, 100, 1 end
        
        -- Mock ptutil methods
        ptutil.getPluginDir = function() return "/plugin/dir" end
        ptutil.isPathChooser = function() return false end
        ptutil.showProgressBar = function() return 100, true end -- Default to showing progress bar
        ptutil.grid_defaults = {
            progress_bar_max_size = 100,
            progress_bar_pages_per_pixel = 1,
            progress_bar_min_size = 10,
            stretch_covers = false
        }
        
        -- Mock DocSettings
        DocSettings.hasSidecarFile = function() return false end
        
        MosaicMenu = require("mosaicmenu")
    end)
    
    it("shows both progress bar and text progress when configured", function()
        local render_context = mock_ui.default_render_context()
        render_context.progress_text_format = "status_percent_and_pages"
        render_context.hide_file_info = true
        
        local menu = {
            width = 600,
            screen_w = 600,
            page = 1,
            perpage = 3,
            nb_cols = 3,
            item_margin = 10,
            item_table = {
                { text = "Book 1", file = "/books/book1.epub" },
                { text = "Book 2", file = "/books/book2.epub" },
                { text = "Book 3", file = "/books/book3.epub" }
            },
            item_group = {},
            layout = {},
            items_to_update = {},
            itemnumber = 1,
            getBookInfo = function() return { 
                been_opened = true, 
                status = "reading", 
                percent_finished = 0.5,
                pages = 200 -- Sidecar pages
            } end,
            item_dimen = { copy = function() return { w = 100, h = 100 } end },
            inner_dimen = { w = 600, h = 800 },
            item_width = 100,
            item_height = 100,
            nb_rows_portrait = 1,
            nb_cols_portrait = 3,
            nb_rows_landscape = 1,
            nb_cols_landscape = 3,
            render_context = render_context
        }
        
        -- Mixin MosaicMenu methods
        for k, v in pairs(MosaicMenu) do menu[k] = v end
        
        -- Setup mocks for this test
        ptutil.showProgressBar = function() return 200, true end -- Show progress bar
        
        -- Initialize menu (creates progress_widget)
        menu:_recalculateDimen()
        
        -- Build items
        menu:_updateItemsBuildUI()
        
        -- Find the MosaicMenuItem in the widget tree
        -- item_group[1] is LineWidget
        -- item_group[2] is VerticalSpan
        -- item_group[3] is the row container (CenterContainer or LeftContainer)
        local row_container = menu.item_group[3]
        assert.is_not_nil(row_container)
        assert.is_not_nil(row_container.children, "Row container has no children")
        
        -- Inside row container is HorizontalGroup (cur_row)
        local horizontal_group = row_container.children[1]
        assert.is_not_nil(horizontal_group)
        
        -- Inside HorizontalGroup are items and spans.
        -- We added 3 items.
        -- Structure: Span, Item, Span, Span, Item, Span, Span, Item, Span
        -- Let's find the first MosaicMenuItem
        local item
        -- Note: table.insert adds to the array part of the table, not .children in the mock unless passed to new()
        for i, child in ipairs(horizontal_group) do
            -- MosaicMenuItem is an InputContainer (mocked)
            if child.name == "InputContainer" then
                item = child
                break
            end
        end
        assert.is_not_nil(item, "Could not find MosaicMenuItem in widget tree")
        
        -- Spy on paintTo methods
        -- We need to access the progress_widget instance. It's a local in mosaicmenu.lua, 
        -- but it's created in _recalculateDimen.
        -- Since we can't easily access the local variable, we can spy on the ProgressWidget class paintTo method
        -- IF the instance uses it.
        local ProgressWidget = require("ui/widget/progresswidget")
        local AlphaContainer = require("ui/widget/container/alphacontainer")
        local TextWidget = require("ui/widget/textwidget")
        
        spy.on(ProgressWidget, "paintTo")
        spy.on(AlphaContainer, "paintTo")
        spy.on(TextWidget, "new")
        
        -- Call paintTo on the item
        local bb = {} -- mock blitbuffer
        item:paintTo(bb, 0, 0)
        
        -- Assertions
        assert.spy(ProgressWidget.paintTo).was.called()
        assert.spy(AlphaContainer.paintTo).was.called()
        
        -- Verify text content
        -- Expected: 100/200 (50%) 
        -- Note: T template might add spaces or not depending on implementation, but here T is mocked to return formatted string.
        -- In mock_ui.lua, T is not mocked, but in mosaicmenu.lua it is required from ffi/util.
        -- Wait, T is required in mosaicmenu.lua: local T = require("ffi/util").template
        -- I need to check if ffi/util is mocked. It is not in mock_ui.lua.
        -- But I can check the arguments passed to TextWidget:new
        
        assert.spy(TextWidget.new).was.called()
        -- We need to find the call that created the progress text
        -- TextWidget.new is a spy, so it has .calls property
        local calls = TextWidget.new.calls
        local found_text = false
        for _, call in ipairs(calls) do
            -- TextWidget:new(o) -> call.vals = { self, o }
            local arg = call.vals[2]
            if arg and arg.text and arg.text:match("100/200 %(50%%%)") then
                found_text = true
                break
            end
        end
        assert.is_true(found_text, "Should have created TextWidget with correct progress text")
    end)
end)

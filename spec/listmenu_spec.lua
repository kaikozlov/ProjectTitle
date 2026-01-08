require 'busted.runner'()
local mock_ui = require("spec.support.mock_ui")

describe("ListMenu", function()
    local ListMenu
    local ListMenuItem
    
    setup(function()
        mock_ui()
        
        -- Load the module under test
        -- We need to capture the return value which is ListMenu
        -- But ListMenuItem is local to the file, so we can't access it directly unless we expose it
        -- or test it through ListMenu.
        -- However, ListMenu uses ListMenuItem in _updateItemsBuildUI.
        -- To test ListMenuItem in isolation, we might need to modify the source to return it, 
        -- or just test it via ListMenu integration or by inspecting the global environment if it leaked (it didn't).
        
        -- Wait, ListMenuItem is local. I can't unit test it directly easily without modifying the file.
        -- But I can test ListMenu which uses it.
        -- Or I can use `debug.getupvalue` to get ListMenuItem from ListMenu methods if possible.
        -- ListMenu._updateItemsBuildUI uses ListMenuItem.
        
        ListMenu = require("listmenu")
    end)
    
    describe("ListMenu Logic", function()
        it("recalculates dimensions correctly in portrait", function()
            local menu = {
                inner_dimen = { w = 600, h = 800 },
                item_table = { {}, {}, {} }, -- 3 items
                page = 1,
                files_per_page = 7,
                path_items = {},
                path = "/some/path",
                render_context = mock_ui.default_render_context()
            }
            -- Mixin ListMenu methods
            for k, v in pairs(ListMenu) do menu[k] = v end
            
            menu:_recalculateDimen()
            
            assert.is.equal(7, menu.perpage)
            assert.is.equal(1, menu.page_num)
            assert.is_not_nil(menu.item_height)
        end)
        
        it("builds UI items correctly", function()
            local render_context = mock_ui.default_render_context()
            local menu = {
                width = 600,
                screen_w = 600,
                page = 1,
                perpage = 5,
                item_table = {
                    { text = "Book 1", file = "/books/book1.epub" },
                    { text = "Book 2", file = "/books/book2.epub" },
                    { text = "Folder 1", path = "/books/folder1" } -- directory
                },
                item_group = {},
                layout = {},
                items_to_update = {},
                itemnumber = 1,
                getBookInfo = function() return { been_opened = false, status = "unread" } end,
                item_dimen = { copy = function() return { w = 100, h = 20 } end },
                item_width = 100,
                item_height = 20,
                render_context = render_context
            }
            -- Mixin ListMenu methods
            for k, v in pairs(ListMenu) do menu[k] = v end
            
            -- We need to mock ListMenuItem:new because it's local in listmenu.lua
            -- But we can't easily mock a local variable in the module.
            -- However, since we mocked all UI widgets, ListMenuItem:new should work fine
            -- and return a widget structure.
            
            menu:_updateItemsBuildUI()
            
            assert.is_true(#menu.item_group > 0)
            -- Check if items were added to layout
            assert.is_true(#menu.layout > 0)
        end)
    end)
end)

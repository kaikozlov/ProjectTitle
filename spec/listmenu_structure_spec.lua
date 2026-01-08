require 'busted.runner'()
local mock_ui = require("spec.support.mock_ui")

describe("ListMenu Structure", function()
    local ListMenu
    
    setup(function()
        mock_ui()
        ListMenu = require("listmenu")
    end)
    
    it("places details in a BottomContainer -> RightContainer structure", function()
        local render_context = mock_ui.default_render_context()
        local menu = {
            width = 600,
            screen_w = 600,
            page = 1,
            perpage = 1,
            item_table = {
                { text = "Book 1", file = "/books/book1.epub" }
            },
            item_group = {},
            layout = {},
            items_to_update = {},
            itemnumber = 1,
            getBookInfo = function() return { 
                been_opened = false, 
                status = "reading",
                title = "Book Title",
                authors = "Author Name"
            } end,
            item_dimen = { copy = function() return { w = 600, h = 100 } end },
            item_width = 600,
            item_height = 100,
            cover_specs = false,
            render_context = render_context
        }
        
        -- Mixin ListMenu methods
        for k, v in pairs(ListMenu) do menu[k] = v end
        
        -- Mock BookInfoManager to return info so we enter the "known file" branch
        local BookInfoManager = require("bookinfomanager")
        BookInfoManager.getBookInfo = function() 
            return { 
                title = "Book Title",
                authors = "Author Name",
                pages = 100
            } 
        end
        BookInfoManager.getSetting = function() return nil end
        
        -- Mock ptutil to ensure we are not in pathchooser mode
        local ptutil = require("ptutil")
        ptutil.isPathChooser = function() return false end
        ptutil.formatAuthorSeries = function(a, s) return (a or "") .. (s or "") end
        ptutil.formatTags = function(t) return t end
        ptutil.formatSeries = function(s, i) return s end
        
        menu:_updateItemsBuildUI()
        
        local item = menu.item_group[2] -- 1 is the line, 2 is the item
        assert.is_not_nil(item)
        
        -- Traverse widget tree
        -- ListMenuItem -> UnderlineContainer -> OverlapGroup -> LeftContainer -> HorizontalGroup -> LeftContainer (wbody)
        
        local underline_container = item[1]
        assert.equal("UnderlineContainer", underline_container.name)
        
        local widget = underline_container[1]
        assert.equal("OverlapGroup", widget.name)
        
        -- widget has items added via table.insert, so they are in array part
        local left_container = widget[1]
        assert.equal("LeftContainer", left_container.name)
        
        local wmain = left_container.children[1]
        assert.equal("HorizontalGroup", wmain.name)
        
        local wbody = wmain.children[#wmain.children]
        assert.equal("LeftContainer", wbody.name)
        
        local wbody_overlap = wbody.children[1]
        assert.equal("OverlapGroup", wbody_overlap.name)
        
        -- Inside wbody OverlapGroup, we expect:
        -- 1. TopContainer (metadata)
        -- 2. BottomContainer (details wrapper)
        -- 3. TopContainer/LeftContainer (title)
        
        local found_bottom_container = false
        local found_right_container = false
        
        for _, child in ipairs(wbody_overlap.children) do
            if child.name == "BottomContainer" then
                found_bottom_container = true
                -- Inside BottomContainer -> RightContainer -> HorizontalGroup
                local right_container = child.children[1]
                if right_container and right_container.name == "RightContainer" then
                    found_right_container = true
                    break
                end
            end
        end
        
        assert.is_true(found_bottom_container, "Should have found a BottomContainer in wbody")
        assert.is_true(found_right_container, "Should have found a RightContainer inside BottomContainer")
        
        -- Verify dimensions of RightContainer
        -- wmain_width = dimen.w (600) - wleft_width (0) - wmain_left_padding (10) = 590
        -- We need to find the RightContainer instance again to check dimen
        local right_container_instance
        for _, child in ipairs(wbody_overlap.children) do
            if child.name == "BottomContainer" then
                right_container_instance = child.children[1]
                break
            end
        end
        
        assert.is_not_nil(right_container_instance)
        -- In our mock, dimen is stored in the object if passed to new
        -- The mock Widget:new stores 'o' as 'self', so properties passed to new are on the object
        assert.is_not_nil(right_container_instance.dimen, "RightContainer should have dimen")
        assert.equal(590, right_container_instance.dimen.w, "RightContainer width should be wmain_width (590)")
    end)
end)

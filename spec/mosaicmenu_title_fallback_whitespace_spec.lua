require 'busted.runner'()
local setup_mocks = require("spec.support.mock_ui")

describe("MosaicMenu Title Fallback Whitespace", function()
    local MosaicMenu
    local BookInfoManagerMock
    local ptutilMock
    
    setup(function()
        setup_mocks()
        
        -- Mock BookInfoManager
        BookInfoManagerMock = {
            getSetting = function(self, key)
                if key == "show_mosaic_titles" then return true end
                if key == "show_name_grid_folders" then return true end
                return nil
            end,
            getBookInfo = function(self, filepath, do_cover)
                return {
                    has_cover = true,
                    cover_fetched = true,
                    title = "   ", -- Whitespace title
                    authors = nil,
                    cover_w = 100,
                    cover_h = 150,
                    ignore_cover = false,
                    ignore_meta = false
                }
            end,
            getCachedCoverSize = function() return 100, 150, 1 end
        }
        package.loaded["bookinfomanager"] = BookInfoManagerMock
        
        -- Mock ptutil
        ptutilMock = {
            getPluginDir = function() return "/tmp" end,
            isPathChooser = function() return false end,
            formatAuthors = function(a) return a end,
            grid_defaults = {
                dir_font_nominal = 20,
                dir_font_min = 10,
                progress_bar_max_size = 100,
                progress_bar_pages_per_pixel = 1,
                progress_bar_min_size = 10,
                stretch_covers = false
            },
            showProgressBar = function() return nil, false end,
            onFocus = function() end,
            onUnfocus = function() end,
            separator = { en_dash = "-" },
            title_serif = "font",
            good_serif = "font",
            mediumBlackLine = function() return {} end,
            thinGrayLine = function() return {} end,
            thinWhiteLine = function() return {} end
        }
        package.loaded["ptutil"] = ptutilMock
        
        -- Mock ptdbg
        package.loaded["ptdbg"] = {
            logprefix = "TEST",
            new = function() return { report = function() end } end
        }

        -- Mock other dependencies
        package.loaded["docsettings"] = { hasSidecarFile = function() return false end }
        package.loaded["ui/widget/menu"] = { getMenuText = function(entry) return entry.text end }
        
        MosaicMenu = require("mosaicmenu")
    end)
    
    it("uses filename as fallback when title is whitespace and show_mosaic_titles is true", function()
        local menu = {
            width = 600,
            screen_w = 600,
            page = 1,
            perpage = 6,
            nb_cols = 3,
            item_margin = 10,
            item_table = {
                { text = "filename.pdf", file = "/books/filename.pdf" },
            },
            item_group = {},
            layout = {},
            items_to_update = {},
            itemnumber = 1,
            getBookInfo = function() return { been_opened = false, status = "unread" } end,
            item_dimen = { copy = function() return { w = 100, h = 100 } end },
            inner_dimen = { w = 600, h = 800 },
            item_width = 100,
            item_height = 100,
            _do_cover_images = true,
            _do_hint_opened = false,
            menu = {}
        }
        -- Mixin MosaicMenu methods
        for k, v in pairs(MosaicMenu) do menu[k] = v end
        
        -- Run update items to trigger MosaicMenuItem creation and update
        menu:_updateItemsBuildUI()
        
        local item = menu.layout[1][1]
        local widget = item._underline_container[1]
        
        local column = widget[1] 
        -- column is VerticalGroup
        
        local wrapper = column[1]
        -- wrapper is CenterContainer
        
        local info_container = wrapper[1]
        -- info_container is FrameContainer
        
        local info_vgroup = info_container[1]
        -- info_vgroup is VerticalGroup
        
        local title_widget = info_vgroup[1]
        -- title_widget is TextBoxWidget
        
        assert.is.equal("filename.pdf", title_widget.text)
    end)

    it("uses filename as fallback when title is whitespace in FakeCover (no cover image)", function()
        -- Override getBookInfo for this test
        local original_getBookInfo = BookInfoManagerMock.getBookInfo
        BookInfoManagerMock.getBookInfo = function(self, filepath, do_cover)
            return {
                has_cover = false,
                cover_fetched = true,
                title = "   ",
                authors = nil,
                ignore_cover = false,
                ignore_meta = false
            }
        end
        
        local menu = {
            width = 600,
            screen_w = 600,
            page = 1,
            perpage = 6,
            nb_cols = 3,
            item_margin = 10,
            item_table = {
                { text = "filename.pdf", file = "/books/filename.pdf" },
            },
            item_group = {},
            layout = {},
            items_to_update = {},
            itemnumber = 1,
            getBookInfo = function() return { been_opened = false, status = "unread" } end,
            item_dimen = { copy = function() return { w = 100, h = 100 } end },
            inner_dimen = { w = 600, h = 800 },
            item_width = 100,
            item_height = 100,
            _do_cover_images = true,
            _do_hint_opened = false,
            menu = {}
        }
        -- Mixin MosaicMenu methods
        for k, v in pairs(MosaicMenu) do menu[k] = v end
        
        menu:_updateItemsBuildUI()
        
        local item = menu.layout[1][1]
        local widget = item._underline_container[1]
        local fake_cover = widget[1]
        local center_container = fake_cover[1]
        local vgroup = center_container[1]
        
        local title_widget
        for _, child in ipairs(vgroup) do
            if child.name == "FrameContainer" and child.children[1] and child.children[1].name == "TextBoxWidget" then
                title_widget = child.children[1]
                break
            end
        end
        
        assert.is_not_nil(title_widget, "Title widget should exist")
        local text = title_widget.text:gsub("\u{200B}", "")
        assert.is.equal("filename.pdf", text)
        
        BookInfoManagerMock.getBookInfo = original_getBookInfo
    end)

    it("truncates long filenames in FakeCover", function()
        -- Override getBookInfo for this test
        local original_getBookInfo = BookInfoManagerMock.getBookInfo
        BookInfoManagerMock.getBookInfo = function(self, filepath, do_cover)
            return {
                has_cover = false,
                cover_fetched = true,
                title = "   ",
                authors = nil,
                ignore_cover = false,
                ignore_meta = false
            }
        end
        
        local long_name = string.rep("a", 70) .. ".pdf"
        local menu = {
            width = 600,
            screen_w = 600,
            page = 1,
            perpage = 6,
            nb_cols = 3,
            item_margin = 10,
            item_table = {
                { text = long_name, file = "/books/" .. long_name },
            },
            item_group = {},
            layout = {},
            items_to_update = {},
            itemnumber = 1,
            getBookInfo = function() return { been_opened = false, status = "unread" } end,
            item_dimen = { copy = function() return { w = 100, h = 100 } end },
            inner_dimen = { w = 600, h = 800 },
            item_width = 100,
            item_height = 100,
            _do_cover_images = true,
            _do_hint_opened = false,
            menu = {}
        }
        -- Mixin MosaicMenu methods
        for k, v in pairs(MosaicMenu) do menu[k] = v end
        
        menu:_updateItemsBuildUI()
        
        local item = menu.layout[1][1]
        local widget = item._underline_container[1]
        local fake_cover = widget[1]
        local center_container = fake_cover[1]
        local vgroup = center_container[1]
        
        local title_widget
        for _, child in ipairs(vgroup) do
            if child.name == "FrameContainer" and child.children[1] and child.children[1].name == "TextBoxWidget" then
                title_widget = child.children[1]
                break
            end
        end
        
        assert.is_not_nil(title_widget, "Title widget should exist")
        local text = title_widget.text:gsub("\u{200B}", "")
        assert.is_true(text:match("…$") ~= nil, "Text should be truncated")
        assert.is_true(text:len() < 70, "Text should be shorter than original")
        
        BookInfoManagerMock.getBookInfo = original_getBookInfo
    end)

    it("truncates long filenames when cover is present", function()
        -- Override getBookInfo for this test
        local original_getBookInfo = BookInfoManagerMock.getBookInfo
        BookInfoManagerMock.getBookInfo = function(self, filepath, do_cover)
            return {
                has_cover = true,
                cover_fetched = true,
                cover_bb = {}, -- Mock blitbuffer
                cover_w = 100,
                cover_h = 150,
                title = "   ",
                authors = nil,
                ignore_cover = false,
                ignore_meta = false
            }
        end
        
        local long_name = string.rep("a", 70) .. ".pdf"
        local menu = {
            width = 600,
            screen_w = 600,
            page = 1,
            perpage = 6,
            nb_cols = 3,
            item_margin = 10,
            item_table = {
                { text = long_name, file = "/books/" .. long_name },
            },
            item_group = {},
            layout = {},
            items_to_update = {},
            itemnumber = 1,
            getBookInfo = function() return { been_opened = false, status = "unread" } end,
            item_dimen = { copy = function() return { w = 200, h = 300 } end },
            inner_dimen = { w = 600, h = 800 },
            item_width = 200,
            item_height = 300,
            _do_cover_images = true,
            _do_hint_opened = false,
            menu = {}
        }
        -- Mixin MosaicMenu methods
        for k, v in pairs(MosaicMenu) do menu[k] = v end
        
        menu:_updateItemsBuildUI()
        
        local item = menu.layout[1][1]
        local widget = item._underline_container[1]
        -- widget is CenterContainer
        local column = widget[1]
        -- column is VerticalGroup
        
        -- We expect an info container (FrameContainer) and a cover container (CenterContainer)
        -- If info container was dropped due to size, we won't find it.
        
        local info_container
        for _, child in ipairs(column) do
            if child.name == "CenterContainer" and child.children[1] and child.children[1].name == "FrameContainer" then
                -- This could be the info container or the cover frame.
                -- Info container has a VerticalGroup inside.
                -- Cover frame has an ImageWidget inside.
                local inner = child.children[1]
                if inner.children[1] and inner.children[1].name == "VerticalGroup" then
                    info_container = inner
                    break
                end
            end
        end
        
        assert.is_not_nil(info_container, "Info container should exist (not be dropped due to size)")
        
        local title_widget = info_container.children[1][1]
        assert.is_not_nil(title_widget, "Title widget should exist")
        
        local text = title_widget.text:gsub("\u{200B}", "")
        assert.is_true(text:match("…$") ~= nil, "Text should be truncated")
        assert.is_true(text:len() < 70, "Text should be shorter than original")
        
        BookInfoManagerMock.getBookInfo = original_getBookInfo
    end)
end)

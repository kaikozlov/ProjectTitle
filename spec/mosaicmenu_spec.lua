require 'busted.runner'()
local setup_mocks = require("spec.support.mock_ui")

describe("MosaicMenu", function()
    local MosaicMenu
    local BookInfoManager
    
    setup(function()
        setup_mocks()
        MosaicMenu = require("mosaicmenu")
        BookInfoManager = require("bookinfomanager")
    end)
    
    describe("MosaicMenu Logic", function()
        it("recalculates dimensions correctly", function()
            local menu = {
                inner_dimen = { w = 600, h = 800 },
                item_table = { {}, {}, {}, {}, {} }, -- 5 items
                page = 1,
                nb_cols_portrait = 3,
                nb_rows_portrait = 4,
                nb_cols_landscape = 4,
                nb_rows_landscape = 3
            }
            -- Mixin MosaicMenu methods
            for k, v in pairs(MosaicMenu) do menu[k] = v end
            
            menu:_recalculateDimen()
            
            assert.is.equal(12, menu.perpage) -- 3 * 4
            assert.is.equal(1, menu.page_num)
            assert.is_not_nil(menu.item_height)
            assert.is_not_nil(menu.item_width)
        end)
        
        it("builds UI items correctly", function()
            local original_getBookInfoBatch = BookInfoManager.getBookInfoBatch
            local menu = {
                width = 600,
                screen_w = 600,
                page = 1,
                perpage = 6,
                nb_cols = 3,
                item_margin = 10,
                item_table = {
                    { text = "Book 1", file = "/books/book1.epub" },
                    { text = "Book 2", file = "/books/book2.epub" },
                    { text = "Folder 1", path = "/books/folder1" }
                },
                item_group = {},
                layout = {},
                items_to_update = {},
                itemnumber = 1,
                getBookInfo = function() return { been_opened = false, status = "unread" } end,
                item_dimen = { copy = function() return { w = 100, h = 100 } end },
                inner_dimen = { w = 600, h = 800 },
                item_width = 100,
                item_height = 100
            }
            -- Mixin MosaicMenu methods
            for k, v in pairs(MosaicMenu) do menu[k] = v end

            BookInfoManager.getBookInfoBatch = function(self, filepaths, do_cover)
                local results = {}
                for _, filepath in ipairs(filepaths) do
                    results[filepath] = {
                        has_cover = false,
                        cover_fetched = true,
                        title = "Test Book",
                        authors = "Test Author",
                    }
                end
                return results
            end
            
            menu:_updateItemsBuildUI()

            BookInfoManager.getBookInfoBatch = original_getBookInfoBatch
            
            assert.is_true(#menu.item_group > 0)
            -- Check if items were added to layout
            assert.is_true(#menu.layout > 0)
        end)

        it("does not create a cover_info_cache during mosaic rendering", function()
            local original_getBookInfoBatch = BookInfoManager.getBookInfoBatch
            local menu = {
                width = 600,
                screen_w = 600,
                page = 1,
                perpage = 6,
                nb_cols = 3,
                item_margin = 10,
                item_table = {
                    { text = "Book 1", file = "/books/book1.epub" },
                },
                item_group = {},
                layout = {},
                items_to_update = {},
                itemnumber = 1,
                getBookInfo = function()
                    return { been_opened = true, status = "reading", percent_finished = 0.5, pages = 123 }
                end,
                item_dimen = { copy = function() return { w = 100, h = 100 } end },
                inner_dimen = { w = 600, h = 800 },
                item_width = 100,
                item_height = 100,
                render_context = setup_mocks.default_render_context(),
            }
            for k, v in pairs(MosaicMenu) do menu[k] = v end

            BookInfoManager.getBookInfoBatch = function(self, filepaths, do_cover)
                local results = {}
                for _, filepath in ipairs(filepaths) do
                    results[filepath] = {
                        cover_fetched = true,
                        has_cover = false,
                        pages = 123,
                        title = "Test Book",
                        authors = "Test Author",
                    }
                end
                return results
            end

            menu:_updateItemsBuildUI()

            BookInfoManager.getBookInfoBatch = original_getBookInfoBatch

            assert.is_nil(menu.cover_info_cache)
        end)
    end)
end)

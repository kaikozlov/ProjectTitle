require 'busted.runner'()
local mock_ui = require("spec.support.mock_ui")

describe("ListMenu", function()
    local ListMenu
    local ListMenuItem
    local BookInfoManager
    
	    setup(function()
	        mock_ui()
            package.loaded["bookinfomanager"] = nil
            package.loaded["listmenu"] = nil
            package.loaded["document/documentregistry"] = {
                hasProvider = function() return true end,
                getProvider = function() return {} end,
                openDocument = function() return nil end,
            }
            package.loaded["apps/filemanager/filemanagerbookinfo"] = {
                extendProps = function(props) return props or {} end,
                getCoverImage = function() return nil end,
            }
            package.loaded["ui/widget/infomessage"] = {
                new = function(self, o) return o end,
            }
            package.loaded["ui/renderimage"] = {
                scaleBlitBuffer = function(bb) return bb end,
            }
            package.loaded["ui/uimanager"] = {
                show = function() end,
                close = function() end,
                scheduleIn = function() end,
            }
            package.loaded["ffi/zstd"] = {
                zstd_uncompress_ctx = function() return nil, 0 end,
                zstd_compress = function() return nil, 0 end,
            }
            package.loaded["ui/time"] = {
                now = function() return 0 end,
                s = function(n) return n end,
            }
            package.loaded["device"].canUseWAL = function() return false end
            package.loaded["device"].isAndroid = function() return false end
            package.loaded["device"].enableCPUCores = function() end
            _G.G_reader_settings = {
                readSetting = function() return nil end,
                isTrue = function() return false end,
                nilOrTrue = function() return false end,
            }
	        
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
        
	        BookInfoManager = require("bookinfomanager")
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
            local original_getBookInfoBatch = BookInfoManager.getBookInfoBatch
            local menu = {
                width = 600,
                screen_w = 600,
                page = 1,
                perpage = 5,
                item_table = {
                    { text = "Book 1", file = "/books/book1.epub", path = "/books/book1.epub", is_file = true },
                    { text = "Book 2", file = "/books/book2.epub", path = "/books/book2.epub", is_file = true },
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
            
            -- We need to mock ListMenuItem:new because it's local in listmenu.lua
            -- But we can't easily mock a local variable in the module.
            -- However, since we mocked all UI widgets, ListMenuItem:new should work fine
            -- and return a widget structure.
            
            menu:_updateItemsBuildUI()

            BookInfoManager.getBookInfoBatch = original_getBookInfoBatch
            
            assert.is_true(#menu.item_group > 0)
            -- Check if items were added to layout
            assert.is_true(#menu.layout > 0)
        end)

        it("does not create a cover_info_cache during list rendering", function()
            local render_context = mock_ui.default_render_context()
            local original_getBookInfoBatch = BookInfoManager.getBookInfoBatch
            local menu = {
                width = 600,
                screen_w = 600,
                page = 1,
                perpage = 5,
                item_table = {
                    { text = "Book 1", file = "/books/book1.epub", path = "/books/book1.epub", is_file = true },
                },
                item_group = {},
                layout = {},
                items_to_update = {},
                itemnumber = 1,
                getBookInfo = function()
                    return { been_opened = true, status = "reading", percent_finished = 0.5 }
                end,
                item_dimen = { copy = function() return { w = 100, h = 20 } end },
                item_width = 100,
                item_height = 20,
                render_context = render_context,
            }
            for k, v in pairs(ListMenu) do menu[k] = v end

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

        it("does not fall back to single-item book info lookups for batch misses during initial build", function()
            local render_context = mock_ui.default_render_context()
            local original_getBookInfoBatch = BookInfoManager.getBookInfoBatch
            local original_getBookInfo = BookInfoManager.getBookInfo
            local single_lookup_count = 0
            local menu = {
                width = 600,
                screen_w = 600,
                page = 1,
                perpage = 5,
                item_table = {
                    { text = "Book 1", file = "/books/book1.epub", path = "/books/book1.epub", is_file = true },
                },
                item_group = {},
                layout = {},
                items_to_update = {},
                itemnumber = 1,
                getBookInfo = function()
                    return { been_opened = false, status = "unread" }
                end,
                item_dimen = { copy = function() return { w = 100, h = 20 } end },
                item_width = 100,
                item_height = 20,
                render_context = render_context,
            }
            for k, v in pairs(ListMenu) do menu[k] = v end

            BookInfoManager.getBookInfoBatch = function(self, filepaths, do_cover)
                return {
                    ["/books/book1.epub"] = {
                        _batch_miss = true,
                    },
                }
            end
            BookInfoManager.getBookInfo = function()
                single_lookup_count = single_lookup_count + 1
                return nil
            end

            menu:_updateItemsBuildUI()

            BookInfoManager.getBookInfoBatch = original_getBookInfoBatch
            BookInfoManager.getBookInfo = original_getBookInfo

            assert.equal(0, single_lookup_count)
        end)

        it("clears the page batch after the initial build finishes", function()
            local render_context = mock_ui.default_render_context()
            local original_getBookInfoBatch = BookInfoManager.getBookInfoBatch
            local menu = {
                width = 600,
                screen_w = 600,
                page = 1,
                perpage = 5,
                item_table = {
                    { text = "Book 1", file = "/books/book1.epub", path = "/books/book1.epub", is_file = true },
                },
                item_group = {},
                layout = {},
                items_to_update = {},
                itemnumber = 1,
                getBookInfo = function()
                    return { been_opened = false, status = "unread" }
                end,
                item_dimen = { copy = function() return { w = 100, h = 20 } end },
                item_width = 100,
                item_height = 20,
                render_context = render_context,
            }
            for k, v in pairs(ListMenu) do menu[k] = v end

            BookInfoManager.getBookInfoBatch = function(self, filepaths, do_cover)
                return {
                    ["/books/book1.epub"] = {
                        _batch_miss = true,
                    },
                }
            end

            menu:_updateItemsBuildUI()

            BookInfoManager.getBookInfoBatch = original_getBookInfoBatch

            assert.is_nil(menu._bookinfo_batch)
        end)
    end)
end)

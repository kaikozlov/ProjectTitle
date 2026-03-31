require 'busted.runner'()
local setup_mocks = require("spec.support.mock_ui")

describe("MosaicMenu", function()
    local MosaicMenu
    local MosaicMenuItem
    local BookInfoManager

    local function get_upvalue_by_name(fn, name)
        for index = 1, 20 do
            local upvalue_name, upvalue_value = debug.getupvalue(fn, index)
            if not upvalue_name then
                break
            end
            if upvalue_name == name then
                return upvalue_value
            end
        end
    end
    
    setup(function()
        setup_mocks()
        package.loaded["bookinfomanager"] = nil
        package.loaded["mosaicmenu"] = nil
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
        BookInfoManager = require("bookinfomanager")
        MosaicMenu = require("mosaicmenu")
        MosaicMenuItem = get_upvalue_by_name(MosaicMenu._updateItemsBuildUI, "MosaicMenuItem")
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
                    { text = "Book 1", file = "/books/book1.epub", path = "/books/book1.epub", is_file = true },
                    { text = "Book 2", file = "/books/book2.epub", path = "/books/book2.epub", is_file = true },
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

        it("uses ptutil font fallback in pathchooser folder rendering", function()
            local ui_font = package.loaded["ui/font"]
            local original_get_face = ui_font.getFace
            ui_font.getFace = function()
                error("raw Font:getFace should not be called here")
            end

            local render_context = setup_mocks.default_render_context()
            render_context.is_pathchooser = true

            local menu = {
                width = 600,
                screen_w = 600,
                page = 1,
                perpage = 6,
                nb_cols = 3,
                item_margin = 10,
                item_table = {
                    { text = "Folder 1", path = "/books/folder1" },
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
                render_context = render_context,
            }
            for k, v in pairs(MosaicMenu) do menu[k] = v end

            local ok, err = pcall(function()
                menu:_updateItemsBuildUI()
            end)

            ui_font.getFace = original_get_face

            assert.is_true(ok, err)
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
                    { text = "Book 1", file = "/books/book1.epub", path = "/books/book1.epub", is_file = true },
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

        it("does not fall back to single-item book info lookups for batch misses during initial build", function()
            local original_getBookInfoBatch = BookInfoManager.getBookInfoBatch
            local original_getBookInfo = BookInfoManager.getBookInfo
            local single_lookup_count = 0
            local menu = {
                width = 600,
                screen_w = 600,
                page = 1,
                perpage = 6,
                nb_cols = 3,
                item_margin = 10,
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
                item_dimen = { copy = function() return { w = 100, h = 100 } end },
                inner_dimen = { w = 600, h = 800 },
                item_width = 100,
                item_height = 100,
                render_context = setup_mocks.default_render_context(),
            }
            for k, v in pairs(MosaicMenu) do menu[k] = v end

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

        it("prefetches only file entries for the page batch", function()
            local original_getBookInfoBatch = BookInfoManager.getBookInfoBatch
            local seen_filepaths
            local menu = {
                width = 600,
                screen_w = 600,
                page = 1,
                perpage = 6,
                nb_cols = 3,
                item_margin = 10,
                item_table = {
                    { text = "Book 1", file = "/books/book1.epub", path = "/books/book1.epub", is_file = true },
                    { text = "Folder 1", path = "/books/folder1" },
                    { text = "Go Up", path = "/books/..", is_go_up = true },
                },
                item_group = {},
                layout = {},
                items_to_update = {},
                itemnumber = 1,
                getBookInfo = function()
                    return { been_opened = false, status = "unread" }
                end,
                item_dimen = { copy = function() return { w = 100, h = 100 } end },
                inner_dimen = { w = 600, h = 800 },
                item_width = 100,
                item_height = 100,
                render_context = setup_mocks.default_render_context(),
            }
            for k, v in pairs(MosaicMenu) do menu[k] = v end

            BookInfoManager.getBookInfoBatch = function(self, filepaths, do_cover)
                seen_filepaths = filepaths
                return {
                    ["/books/book1.epub"] = BookInfoManager.BATCH_MISS,
                }
            end

            menu:_updateItemsBuildUI()

            BookInfoManager.getBookInfoBatch = original_getBookInfoBatch

            assert.are.same({ "/books/book1.epub" }, seen_filepaths)
        end)

        it("rebuilds overlays from item-local pathchooser state after another menu updates", function()
            local function make_menu(is_pathchooser)
                local render_context = setup_mocks.default_render_context()
                render_context.is_pathchooser = is_pathchooser
                render_context.series_mode = "series_in_separate_line"
                return {
                    render_context = render_context,
                    getBookInfo = function()
                        return {
                            been_opened = true,
                            status = "reading",
                            percent_finished = 0.5,
                            pages = 120,
                        }
                    end,
                    _bookinfo_batch = {
                        ["/books/book.epub"] = {
                            cover_fetched = true,
                            has_cover = false,
                            title = "Book",
                            authors = "Author",
                            series = "Series",
                            series_index = 1,
                            pages = 120,
                        },
                    },
                }
            end

            local normal_item = MosaicMenuItem:new {
                height = 160,
                width = 120,
                entry = { text = "Book", file = "/books/book.epub", path = "/books/book.epub", is_file = true },
                text = "Book",
                show_parent = {},
                mandatory = "120",
                dimen = { x = 0, y = 0, w = 120, h = 160, copy = function(self) return { x = self.x, y = self.y, w = self.w, h = self.h } end },
                menu = make_menu(false),
                do_cover_image = false,
                do_hint_opened = false,
            }
            local pathchooser_item = MosaicMenuItem:new {
                height = 160,
                width = 120,
                entry = { text = "Book", file = "/books/book.epub", path = "/books/book.epub", is_file = true },
                text = "Book",
                show_parent = {},
                mandatory = "120",
                dimen = { x = 0, y = 0, w = 120, h = 160, copy = function(self) return { x = self.x, y = self.y, w = self.w, h = self.h } end },
                menu = make_menu(true),
                do_cover_image = false,
                do_hint_opened = false,
            }

            normal_item._series_widget = nil
            normal_item:buildOverlayWidgets()

            assert.is_not_nil(pathchooser_item)
            assert.is_not_nil(normal_item._series_widget)
        end)

        it("does not repeat getBookInfo lookups while building mosaic overlays", function()
            local get_book_info_calls = 0
            local render_context = setup_mocks.default_render_context()
            render_context.hide_file_info = true

            local item = MosaicMenuItem:new {
                height = 160,
                width = 120,
                entry = { text = "Book", file = "/books/book.epub", path = "/books/book.epub", is_file = true },
                text = "Book",
                show_parent = {},
                mandatory = "120",
                dimen = { x = 0, y = 0, w = 120, h = 160, copy = function(self) return { x = self.x, y = self.y, w = self.w, h = self.h } end },
                menu = {
                    render_context = render_context,
                    getBookInfo = function()
                        get_book_info_calls = get_book_info_calls + 1
                        return {
                            been_opened = true,
                            status = "reading",
                            percent_finished = 0.5,
                            pages = 120,
                        }
                    end,
                    _bookinfo_batch = {
                        ["/books/book.epub"] = {
                            cover_fetched = true,
                            has_cover = false,
                            title = "Book",
                            authors = "Author",
                            pages = 120,
                        },
                    },
                },
                do_cover_image = false,
                do_hint_opened = false,
            }

            assert.is_not_nil(item)
            assert.equal(1, get_book_info_calls)
        end)
    end)
end)

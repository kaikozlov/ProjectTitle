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
            isImageFile = function(_, filepath)
                return filepath and filepath:match("%.png$")
            end,
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
        local function has_widget_named(node, name)
            if type(node) ~= "table" then
                return false
            end
            if node.name == name then
                return true
            end
            for _, child in ipairs(node.children or {}) do
                if has_widget_named(child, name) then
                    return true
                end
            end
            for i = 1, #node do
                if has_widget_named(node[i], name) then
                    return true
                end
            end
            return false
        end

        local function collect_texts(node, texts)
            texts = texts or {}
            if type(node) ~= "table" then
                return texts
            end
            if type(node.text) == "string" and node.text ~= "" then
                texts[#texts + 1] = node.text
            end
            for _, child in ipairs(node.children or {}) do
                collect_texts(child, texts)
            end
            for i = 1, #node do
                collect_texts(node[i], texts)
            end
            return texts
        end

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

        it("uses the configured mosaic renderer for chooser book files", function()
            local render_context = setup_mocks.default_render_context()
            render_context.is_pathchooser = true

            local item = MosaicMenuItem:new {
                width = 120,
                height = 160,
                entry = { text = "book.epub", file = "/chooser/book.epub", path = "/chooser/book.epub", is_file = true },
                text = "book.epub",
                show_parent = {},
                mandatory = "1 MB",
                dimen = { x = 0, y = 0, w = 120, h = 160, copy = function(self) return { x = self.x, y = self.y, w = self.w, h = self.h } end },
                menu = {
                    render_context = render_context,
                    getBookInfo = function()
                        return { been_opened = true, status = "reading", percent_finished = 0.25, pages = 400 }
                    end,
                    _bookinfo_batch = {
                        ["/chooser/book.epub"] = {
                            cover_fetched = true,
                            has_cover = false,
                            ignore_cover = nil,
                            ignore_meta = nil,
                            title = "Test Book",
                            authors = "Test Author",
                            pages = 400,
                        },
                    },
                },
                do_cover_image = false,
                do_hint_opened = false,
            }

            local texts = collect_texts(item._underline_container[1])

            assert.is_true(item.bookinfo_found)
            assert.is_true(table.concat(texts, "\n"):find("Test Author", 1, true) ~= nil)
        end)

        it("uses the configured mosaic renderer for chooser folders", function()
            local render_context = setup_mocks.default_render_context()
            render_context.is_pathchooser = true
            render_context.show_name_grid_folders = true

            local item = MosaicMenuItem:new {
                width = 120,
                height = 160,
                entry = { text = "Folder/", path = "/chooser/folder" },
                text = "Folder/",
                show_parent = {},
                mandatory = "3 books",
                dimen = { x = 0, y = 0, w = 120, h = 160, copy = function(self) return { x = self.x, y = self.y, w = self.w, h = self.h } end },
                menu = {
                    render_context = render_context,
                    getBookInfo = function()
                        return { been_opened = false, status = "unread" }
                    end,
                },
                do_cover_image = true,
                do_hint_opened = false,
            }

            assert.is_true(has_widget_named(item._underline_container[1], "ImageWidget"))
        end)

        it("starts directory text fitting at the nominal font size", function()
            local ptutil = package.loaded["ptutil"]
            local original_get_font_face = ptutil.getFontFace
            local requested_sizes = {}
            ptutil.getFontFace = function(font_name, size)
                requested_sizes[#requested_sizes + 1] = size
                return { size = size }
            end

            local render_context = setup_mocks.default_render_context()
            render_context.disable_auto_foldercovers = true
            MosaicMenuItem:new {
                width = 120,
                height = 160,
                entry = { text = "Narrow directory", path = "/books/narrow" },
                text = "Narrow directory",
                show_parent = {},
                mandatory = "3 books",
                dimen = {
                    x = 0, y = 0, w = 120, h = 160,
                    copy = function(self)
                        return { x = self.x, y = self.y, w = self.w, h = self.h }
                    end,
                },
                menu = {
                    render_context = render_context,
                    getBookInfo = function()
                        return { been_opened = false, status = "unread" }
                    end,
                },
                do_cover_image = true,
                do_hint_opened = false,
            }

            ptutil.getFontFace = original_get_font_face
            assert.equal(ptutil.grid_defaults.dir_font_nominal, requested_sizes[1])
        end)

        it("decrements directory font size by the configured step, never clamping early", function()
            local ptutil = package.loaded["ptutil"]
            local original_get_font_face = ptutil.getFontFace
            local requested_sizes = {}
            ptutil.getFontFace = function(font_name, size)
                requested_sizes[#requested_sizes + 1] = size
                return { size = size }
            end
            local TextWidget = package.loaded["ui/widget/textwidget"]
            local original_is_truncated = TextWidget.isTruncated
            local original_free = TextWidget.free
            local free_calls = 0
            -- Truncate only the directory text (the one with max_width set);
            -- the buggy math.min clamp made its first truncation jump 22 -> 18,
            -- skipping 20.
            TextWidget.isTruncated = function(self)
                return self.text and self.text:find("Narrow directory", 1, true) ~= nil
            end
            TextWidget.free = function(self)
                if self.text and self.text:find("Narrow directory", 1, true) ~= nil then
                    free_calls = free_calls + 1
                end
            end

            local render_context = setup_mocks.default_render_context()
            render_context.disable_auto_foldercovers = true
            MosaicMenuItem:new {
                width = 120,
                height = 160,
                entry = { text = "Narrow directory", path = "/books/narrow" },
                text = "Narrow directory",
                show_parent = {},
                mandatory = "3 books",
                dimen = {
                    x = 0, y = 0, w = 120, h = 160,
                    copy = function(self)
                        return { x = self.x, y = self.y, w = self.w, h = self.h }
                    end,
                },
                menu = {
                    render_context = render_context,
                    getBookInfo = function()
                        return { been_opened = false, status = "unread" }
                    end,
                },
                do_cover_image = true,
                do_hint_opened = false,
            }

            ptutil.getFontFace = original_get_font_face
            TextWidget.isTruncated = original_is_truncated
            TextWidget.free = original_free

            -- The ladder must step by fontsize_dec_step through every
            -- intermediate size down to dir_font_min. The old math.min clamp
            -- collapsed the first truncation straight to dir_font_min.
            local step = ptutil.grid_defaults.fontsize_dec_step
            local expected_size = ptutil.grid_defaults.dir_font_nominal
            local index = 1
            while expected_size >= ptutil.grid_defaults.dir_font_min do
                assert.equal(expected_size, requested_sizes[index],
                    "directory text ladder broke at step " .. index)
                expected_size = expected_size - step
                index = index + 1
            end
            -- Every rejected ladder widget must be freed before rebuilding:
            -- 5 builds (22,21,20,19,18), the first 4 rejected and freed.
            assert.equal(4, free_calls)
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

        it("frees rejected mosaic title overlay trees", function()
            local FrameContainer = package.loaded["ui/widget/container/framecontainer"]
            local original_new = FrameContainer.new
            local created_info_containers = 0
            local freed_info_containers = 0
            FrameContainer.new = function(self, opts)
                local widget = original_new(self, opts)
                if opts and opts.background == 0 and opts[1] and opts[1].name == "VerticalGroup" then
                    created_info_containers = created_info_containers + 1
                    local original_free = widget.free
                    widget.free = function(this, ...)
                        freed_info_containers = freed_info_containers + 1
                        return original_free(this, ...)
                    end
                end
                return widget
            end

            local render_context = setup_mocks.default_render_context()
            render_context.show_mosaic_titles = true
            MosaicMenuItem:new {
                height = 80,
                width = 120,
                entry = { text = "Book", file = "/books/book.epub" },
                text = "Book",
                show_parent = {},
                mandatory = "100",
                dimen = {
                    x = 0, y = 0, w = 120, h = 80,
                    copy = function(self)
                        return { x = self.x, y = self.y, w = self.w, h = self.h }
                    end,
                },
                menu = {
                    render_context = render_context,
                    getBookInfo = function()
                        return { been_opened = false, status = "unread" }
                    end,
                    _bookinfo_batch = {
                        ["/books/book.epub"] = {
                            cover_fetched = true,
                            has_cover = true,
                            cover_bb = {},
                            cover_w = 100,
                            cover_h = 150,
                            title = "A title",
                            authors = "An author",
                        },
                    },
                },
                do_cover_image = true,
                do_hint_opened = false,
            }

            FrameContainer.new = original_new
            assert.equal(2, created_info_containers)
            assert.equal(created_info_containers, freed_info_containers)
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
                    { text = "Collection Book", file = "/books/collection.epub" },
                    { text = "Browser Book", path = "/books/browser.epub", is_file = true },
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
                    ["/books/collection.epub"] = BookInfoManager.BATCH_MISS,
                    ["/books/browser.epub"] = BookInfoManager.BATCH_MISS,
                }
            end
            menu:_updateItemsBuildUI()

            BookInfoManager.getBookInfoBatch = original_getBookInfoBatch

            assert.are.same({ "/books/collection.epub", "/books/browser.epub" }, seen_filepaths)
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

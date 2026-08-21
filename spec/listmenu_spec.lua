require 'busted.runner'()
local mock_ui = require("spec.support.mock_ui")

describe("ListMenu", function()
    local ListMenu
    local ListMenuItem
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
	        mock_ui()
            package.loaded["bookinfomanager"] = nil
            package.loaded["listmenu"] = nil
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
            ListMenuItem = get_upvalue_by_name(ListMenu._updateItemsBuildUI, "ListMenuItem")
	    end)
    
    describe("ListMenu Logic", function()
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

        it("does not queue unsupported pathchooser files for background extraction when batch data marks them unsupported", function()
            local render_context = mock_ui.default_render_context()
            local original_getBookInfoBatch = BookInfoManager.getBookInfoBatch
            local menu = {
                width = 600,
                screen_w = 600,
                page = 1,
                perpage = 5,
                item_table = {
                    { text = "note.txt", file = "/pathchooser/note.txt", path = "/pathchooser/note.txt", is_file = true },
                },
                item_group = {},
                layout = {},
                items_to_update = {},
                itemnumber = 1,
                getBookInfo = function()
                    return { been_opened = false, status = "unread" }
                end,
                item_dimen = { copy = function() return { w = 100, h = 48 } end },
                item_width = 100,
                item_height = 48,
                render_context = render_context,
                _do_cover_images = false,
                _do_filename_only = false,
                _do_hint_opened = false,
            }
            render_context.is_pathchooser = true
            for k, v in pairs(ListMenu) do menu[k] = v end

            BookInfoManager.getBookInfoBatch = function()
                return {
                    ["/pathchooser/note.txt"] = {
                        cover_fetched = "Y",
                        ignore_cover = "Y",
                        ignore_meta = "Y",
                        _no_provider = true,
                    },
                }
            end

            menu:_updateItemsBuildUI()

            BookInfoManager.getBookInfoBatch = original_getBookInfoBatch

            assert.equal(0, #menu.items_to_update)
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

        it("stores pathchooser state on each list item instance", function()
            local function make_menu(is_pathchooser)
                return {
                    render_context = {
                        is_pathchooser = is_pathchooser,
                        is_touch_device = true,
                        force_focus_indicator = false,
                        disable_auto_foldercovers = true,
                    },
                    getBookInfo = function()
                        return { been_opened = false, status = "unread" }
                    end,
                    _bookinfo_batch = {},
                }
            end

            local pathchooser_item = ListMenuItem:new {
                height = 32,
                width = 200,
                entry = { text = "Folder/", path = "/chooser/folder" },
                text = "Folder/",
                show_parent = {},
                mandatory = "",
                dimen = { x = 0, y = 0, w = 200, h = 32, copy = function(self) return { x = self.x, y = self.y, w = self.w, h = self.h } end },
                menu = make_menu(true),
                do_cover_image = false,
                do_filename_only = false,
                do_hint_opened = false,
            }
            local browser_item = ListMenuItem:new {
                height = 32,
                width = 200,
                entry = { text = "Folder/", path = "/browser/folder" },
                text = "Folder/",
                show_parent = {},
                mandatory = "",
                dimen = { x = 0, y = 0, w = 200, h = 32, copy = function(self) return { x = self.x, y = self.y, w = self.w, h = self.h } end },
                menu = make_menu(false),
                do_cover_image = false,
                do_filename_only = false,
                do_hint_opened = false,
            }

            assert.is_true(pathchooser_item.is_pathchooser)
            assert.is_false(browser_item.is_pathchooser)
        end)

        it("uses the rich list renderer for chooser book files", function()
            local item = ListMenuItem:new {
                height = 48,
                width = 240,
                entry = { text = "book.epub", file = "/chooser/book.epub", path = "/chooser/book.epub", is_file = true },
                text = "book.epub",
                show_parent = {},
                mandatory = "1 MB",
                dimen = { x = 0, y = 0, w = 240, h = 48, copy = function(self) return { x = self.x, y = self.y, w = self.w, h = self.h } end },
                menu = {
                    render_context = {
                        is_pathchooser = true,
                        is_touch_device = true,
                        force_focus_indicator = false,
                        disable_auto_foldercovers = true,
                    },
                    getBookInfo = function()
                        return { been_opened = false, status = "reading", percent_finished = 0.25, pages = 400 }
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
                do_cover_image = true,
                do_filename_only = false,
                do_hint_opened = false,
            }

            local texts = collect_texts(item._underline_container[1])

            assert.is_true(has_widget_named(item._underline_container[1], "ImageWidget"))
            assert.is_true(item.bookinfo_found)
            assert.is_true(table.concat(texts, "\n"):find("Test Author", 1, true) ~= nil)
        end)

        it("uses the configured list renderer for chooser folders", function()
            local item = ListMenuItem:new {
                height = 48,
                width = 240,
                entry = { text = "Folder/", path = "/chooser/folder" },
                text = "Folder/",
                show_parent = {},
                mandatory = "2 \u{F114} 6 \u{F016}",
                dimen = { x = 0, y = 0, w = 240, h = 48, copy = function(self) return { x = self.x, y = self.y, w = self.w, h = self.h } end },
                menu = {
                    render_context = {
                        is_pathchooser = true,
                        is_touch_device = true,
                        force_focus_indicator = false,
                        disable_auto_foldercovers = true,
                    },
                    getBookInfo = function()
                        return { been_opened = false, status = "unread" }
                    end,
                    _bookinfo_batch = {},
                },
                do_cover_image = true,
                do_filename_only = false,
                do_hint_opened = false,
            }

            local texts = collect_texts(item._underline_container[1])

            assert.is_true(has_widget_named(item._underline_container[1], "ImageWidget"))
            assert.is_true(table.concat(texts, "\n"):find("Folders", 1, true) ~= nil)
            assert.is_true(table.concat(texts, "\n"):find("Books", 1, true) ~= nil)
        end)

        it("prefetches only file entries for the page batch", function()
            local render_context = mock_ui.default_render_context()
            local original_getBookInfoBatch = BookInfoManager.getBookInfoBatch
            local seen_filepaths
            local menu = {
                width = 600,
                screen_w = 600,
                page = 1,
                perpage = 5,
                item_table = {
                    { text = "History Book", file = "/books/history.epub" },
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
                item_dimen = { copy = function() return { w = 100, h = 20 } end },
                item_width = 100,
                item_height = 20,
                render_context = render_context,
            }
            for k, v in pairs(ListMenu) do menu[k] = v end

            BookInfoManager.getBookInfoBatch = function(self, filepaths, do_cover)
                seen_filepaths = filepaths
                return {
                    ["/books/history.epub"] = BookInfoManager.BATCH_MISS,
                    ["/books/browser.epub"] = BookInfoManager.BATCH_MISS,
                }
            end
            menu:_updateItemsBuildUI()

            BookInfoManager.getBookInfoBatch = original_getBookInfoBatch

            assert.are.same({ "/books/history.epub", "/books/browser.epub" }, seen_filepaths)
        end)

        it("skips page batch prefetch in filename-only mode", function()
            local render_context = mock_ui.default_render_context()
            local original_getBookInfoBatch = BookInfoManager.getBookInfoBatch
            local batch_calls = 0
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
                _do_cover_images = false,
                _do_filename_only = true,
            }
            for k, v in pairs(ListMenu) do menu[k] = v end

            BookInfoManager.getBookInfoBatch = function(self, filepaths, do_cover)
                batch_calls = batch_calls + 1
                return {}
            end

            menu:_updateItemsBuildUI()

            BookInfoManager.getBookInfoBatch = original_getBookInfoBatch

            assert.equal(0, batch_calls)
        end)

        it("skips all metadata and progress work in filename-only mode", function()
            local render_context = mock_ui.default_render_context()
            local original_getBookInfoBatch = BookInfoManager.getBookInfoBatch
            local original_getBookInfo = BookInfoManager.getBookInfo
            local ProgressWidget = package.loaded["ui/widget/progresswidget"]
            local original_progress_new = ProgressWidget.new
            local ptutil = package.loaded["ptutil"]
            local original_show_progress_bar = ptutil.showProgressBar
            local plugin_lookup_count = 0
            local core_lookup_count = 0
            local progress_widget_count = 0
            local progress_layout_count = 0
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
                    core_lookup_count = core_lookup_count + 1
                    return {
                        been_opened = true,
                        status = "reading",
                        percent_finished = 0.5,
                        pages = 100,
                    }
                end,
                item_dimen = { copy = function() return { w = 100, h = 20 } end },
                item_width = 100,
                item_height = 20,
                render_context = render_context,
                _do_cover_images = false,
                _do_filename_only = true,
            }
            for k, v in pairs(ListMenu) do menu[k] = v end

            BookInfoManager.getBookInfoBatch = function()
                error("filename-only mode should not batch plugin book info")
            end
            BookInfoManager.getBookInfo = function()
                plugin_lookup_count = plugin_lookup_count + 1
                return nil
            end
            ProgressWidget.new = function(self, opts)
                progress_widget_count = progress_widget_count + 1
                return original_progress_new(self, opts)
            end
            ptutil.showProgressBar = function(...)
                progress_layout_count = progress_layout_count + 1
                return original_show_progress_bar(...)
            end

            menu:_updateItemsBuildUI()

            BookInfoManager.getBookInfoBatch = original_getBookInfoBatch
            BookInfoManager.getBookInfo = original_getBookInfo
            ProgressWidget.new = original_progress_new
            ptutil.showProgressBar = original_show_progress_bar

            assert.equal(0, plugin_lookup_count)
            assert.equal(0, core_lookup_count)
            assert.equal(0, progress_widget_count)
            assert.equal(0, progress_layout_count)
        end)

        it("does not queue filename-only items for background extraction", function()
            local render_context = mock_ui.default_render_context()
            local original_getBookInfoBatch = BookInfoManager.getBookInfoBatch
            local original_getBookInfo = BookInfoManager.getBookInfo
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
                _do_cover_images = false,
                _do_filename_only = true,
            }
            for k, v in pairs(ListMenu) do menu[k] = v end

            BookInfoManager.getBookInfoBatch = function()
                error("filename-only mode should not batch plugin book info")
            end
            BookInfoManager.getBookInfo = function()
                return nil
            end

            menu:_updateItemsBuildUI()

            BookInfoManager.getBookInfoBatch = original_getBookInfoBatch
            BookInfoManager.getBookInfo = original_getBookInfo

            assert.same({}, menu.items_to_update)
        end)
    end)
end)

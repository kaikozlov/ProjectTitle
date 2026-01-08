--[[
    End-to-End Performance Tests

    These tests verify that the plugin meets overall performance targets
    after all optimizations have been applied.

    Run with: busted spec/performance/e2e_spec.lua
]]

local mock_ui = require("spec.support.mock_ui")

describe("End-to-End Performance", function()

    local MosaicMenu
    local ListMenu
    local BookInfoManager
    local ptutil

    -- Helper to create a mosaic menu
    local function create_mosaic_menu(opts)
        opts = opts or {}
        local item_count = opts.item_count or 9
        local item_table = {}
        for i = 1, item_count do
            table.insert(item_table, {
                text = "Book " .. i,
                file = "/books/book" .. i .. ".epub",
                path = "/books/book" .. i .. ".epub",
                is_file = true,
            })
        end

        return {
            inner_dimen = { w = 600, h = 800 },
            item_table = item_table,
            page = 1,
            perpage = opts.perpage or 9,
            nb_cols = opts.nb_cols or 3,
            nb_rows = opts.nb_rows or 3,
            nb_cols_portrait = 3,
            nb_rows_portrait = 3,
            portrait_mode = true,
            item_margin = 10,
            item_width = 180,
            item_height = 240,
            item_dimen = {
                w = 180, h = 240,
                copy = function(self) return { w = self.w, h = self.h } end
            },
            item_group = { clear = function() end },
            layout = {},
            items_to_update = {},
            itemnumber = 1,
            recent_boundary_index = 0,
            getBookInfo = function() return { been_opened = false, status = "unread" } end,
            render_context = opts.render_context or mock_ui.default_render_context(),
            _has_cover_images = false,
            _do_cover_images = true,
            _do_center_partial_rows = true,
            _do_hint_opened = true,
            no_refresh_covers = false,
            width = 600,
            screen_w = 600,
        }
    end

    -- Helper to create a list menu
    local function create_list_menu(opts)
        opts = opts or {}
        local item_count = opts.item_count or 7
        local item_table = {}
        for i = 1, item_count do
            table.insert(item_table, {
                text = "Book " .. i,
                file = "/books/book" .. i .. ".epub",
                path = "/books/book" .. i .. ".epub",
                is_file = true,
            })
        end

        return {
            inner_dimen = { w = 600, h = 800 },
            item_table = item_table,
            page = 1,
            perpage = opts.perpage or 7,
            item_margin = 5,
            item_width = 580,
            item_height = 100,
            item_dimen = {
                w = 580, h = 100,
                copy = function(self) return { w = self.w, h = self.h } end
            },
            item_group = { clear = function() end },
            layout = {},
            items_to_update = {},
            itemnumber = 1,
            recent_boundary_index = 0,
            getBookInfo = function() return { been_opened = false, status = "unread" } end,
            render_context = opts.render_context or mock_ui.default_render_context(),
            _has_cover_images = false,
            _do_cover_images = true,
            _do_hint_opened = true,
            _do_filename_only = false,
            no_refresh_covers = false,
            width = 600,
            screen_w = 600,
        }
    end

    setup(function()
        -- Set up all mocks
        mock_ui()

        -- Additional mocks
        package.loaded["ui/uimanager"] = {
            show = function() end,
            close = function() end,
            scheduleIn = function() end,
            unschedule = function() end,
            nextTick = function() end,
            setDirty = function() end,
        }

        MosaicMenu = require("mosaicmenu")
        ListMenu = require("listmenu")
        BookInfoManager = require("bookinfomanager")
        ptutil = require("ptutil")

        -- Add getBookInfoBatch mock if it doesn't exist or is nil
        if not BookInfoManager.getBookInfoBatch then
            BookInfoManager.getBookInfoBatch = function(self, filepaths, do_cover)
                local results = {}
                for _, path in ipairs(filepaths) do
                    results[path] = {
                        has_cover = false,
                        cover_fetched = true,
                        title = "Test Book",
                        authors = "Test Author",
                    }
                end
                return results
            end
        end
    end)

    describe("Render Performance", function()
        it("renders mosaic page with 9 items in under 100ms", function()
            local render_context = mock_ui.default_render_context()
            local menu = create_mosaic_menu({
                perpage = 9,
                nb_cols = 3,
                nb_rows = 3,
                item_count = 9,
                render_context = render_context,
            })

            -- Mixin MosaicMenu methods
            for k, v in pairs(MosaicMenu) do menu[k] = v end

            -- Measure build time
            local start_time = os.clock()
            menu:_updateItemsBuildUI()
            local elapsed = (os.clock() - start_time) * 1000

            -- Verify it completes in under 100ms
            assert.is_true(elapsed < 100, string.format(
                "Mosaic page render took %.2fms, expected < 100ms", elapsed))
        end)

        it("renders list page with 7 items in under 100ms", function()
            local render_context = mock_ui.default_render_context()
            local menu = create_list_menu({
                perpage = 7,
                item_count = 7,
                render_context = render_context,
            })

            -- Mixin ListMenu methods
            for k, v in pairs(ListMenu) do menu[k] = v end

            -- Measure build time
            local start_time = os.clock()
            menu:_updateItemsBuildUI()
            local elapsed = (os.clock() - start_time) * 1000

            assert.is_true(elapsed < 100, string.format(
                "List page render took %.2fms, expected < 100ms", elapsed))
        end)
    end)

    describe("Database Query Efficiency", function()
        it("uses batch query for multiple items", function()
            local batch_query_count = 0

            -- Track batch queries
            local original_getBookInfoBatch = BookInfoManager.getBookInfoBatch
            BookInfoManager.getBookInfoBatch = function(self, filepaths, do_cover)
                batch_query_count = batch_query_count + 1
                local results = {}
                for _, path in ipairs(filepaths) do
                    results[path] = {
                        has_cover = false,
                        cover_fetched = true,
                        title = "Test Book",
                        authors = "Test Author",
                    }
                end
                return results
            end

            -- Create menu and render
            local render_context = mock_ui.default_render_context()
            local menu = create_mosaic_menu({
                perpage = 9,
                nb_cols = 3,
                nb_rows = 3,
                item_count = 9,
                render_context = render_context,
            })
            for k, v in pairs(MosaicMenu) do menu[k] = v end
            menu:_updateItemsBuildUI()

            -- Restore original function
            BookInfoManager.getBookInfoBatch = original_getBookInfoBatch

            -- Verify batch query was used
            assert.is_true(batch_query_count >= 1,
                "Expected at least 1 batch query, got " .. batch_query_count)
        end)
    end)

    describe("Memory Efficiency", function()
        it("memory growth stays under 1MB for 10 page navigations", function()
            local render_context = mock_ui.default_render_context()

            -- Force initial garbage collection
            collectgarbage("collect")
            local initial_memory = collectgarbage("count")

            -- Simulate 10 page navigations
            for i = 1, 10 do
                local menu = create_mosaic_menu({
                    perpage = 9,
                    nb_cols = 3,
                    nb_rows = 3,
                    item_count = 9,
                    render_context = render_context,
                })
                for k, v in pairs(MosaicMenu) do menu[k] = v end
                menu:_updateItemsBuildUI()

                -- Clear the menu (simulate page change)
                menu.item_group = {}
                menu.layout = {}
            end

            -- Force garbage collection
            collectgarbage("collect")
            local final_memory = collectgarbage("count")

            local memory_growth_kb = final_memory - initial_memory
            local memory_growth_mb = memory_growth_kb / 1024

            -- Allow for some growth but keep it under 1MB
            assert.is_true(memory_growth_mb < 1.0, string.format(
                "Memory grew by %.2f MB, expected < 1.0 MB", memory_growth_mb))
        end)
    end)

    describe("Optimization Integration", function()
        it("uses render_context for settings instead of getSetting", function()
            local get_setting_calls = 0

            -- Track getSetting calls during render
            local original_getSetting = BookInfoManager.getSetting
            BookInfoManager.getSetting = function(self, key)
                get_setting_calls = get_setting_calls + 1
                return nil
            end

            -- Create menu with render_context already populated
            local render_context = mock_ui.default_render_context()
            local menu = create_mosaic_menu({
                perpage = 9,
                nb_cols = 3,
                item_count = 9,
                render_context = render_context,
            })
            for k, v in pairs(MosaicMenu) do menu[k] = v end

            -- Reset counter after menu creation
            get_setting_calls = 0

            -- Render the page
            menu:_updateItemsBuildUI()

            -- Restore
            BookInfoManager.getSetting = original_getSetting

            -- During _updateItemsBuildUI, getSetting calls should be minimal
            -- (some may still occur in subroutines, but should be much fewer than perpage*N)
            -- With optimizations, we expect <10 calls instead of 50+ without optimization
            assert.is_true(get_setting_calls < 50, string.format(
                "Expected fewer than 50 getSetting calls during render (got %d)", get_setting_calls))
        end)

        it("uses cached isPathChooser value from render_context", function()
            local is_pathchooser_calls = 0

            -- Track isPathChooser calls
            local original_isPathChooser = ptutil.isPathChooser
            ptutil.isPathChooser = function(self)
                is_pathchooser_calls = is_pathchooser_calls + 1
                return false
            end

            -- Create menu with is_pathchooser already in render_context
            local render_context = mock_ui.default_render_context()
            render_context.is_pathchooser = false
            local menu = create_mosaic_menu({
                perpage = 9,
                nb_cols = 3,
                item_count = 9,
                render_context = render_context,
            })
            for k, v in pairs(MosaicMenu) do menu[k] = v end

            -- Reset counter
            is_pathchooser_calls = 0

            -- Render
            menu:_updateItemsBuildUI()

            -- Restore
            ptutil.isPathChooser = original_isPathChooser

            -- isPathChooser should not be called during render when cached
            assert.is_true(is_pathchooser_calls == 0, string.format(
                "Expected 0 isPathChooser calls, got %d", is_pathchooser_calls))
        end)
    end)
end)

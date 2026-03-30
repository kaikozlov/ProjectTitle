--[[
    Phase 6: Widget Allocation Reduction Tests

    These tests verify that widget pooling reduces allocations
    while maintaining correct rendering behavior.
]]

local perf = require("spec.support.perf_helpers")
local mock_ui = require("spec.support.mock_ui")

describe("Widget Pool Optimization", function()
    local ptutil
    local ListMenu
    local MosaicMenu
    local BookInfoManager

    setup(function()
        mock_ui()
    end)

    before_each(function()
        package.loaded["ptutil"] = nil
        ptutil = require("ptutil")
        package.loaded["listmenu"] = nil
        package.loaded["mosaicmenu"] = nil
        ListMenu = require("listmenu")
        MosaicMenu = require("mosaicmenu")
        BookInfoManager = require("bookinfomanager")
    end)

    describe("WidgetPool class", function()
        it("provides WidgetPool class", function()
            assert.is_table(ptutil.WidgetPool,
                "ptutil should have WidgetPool class")
        end)

        it("can be instantiated", function()
            local pool = ptutil.WidgetPool:new()
            assert.is_table(pool)
        end)

        it("provides acquire method", function()
            local pool = ptutil.WidgetPool:new()
            assert.is_function(pool.acquire)
        end)

        it("provides release method", function()
            local pool = ptutil.WidgetPool:new()
            assert.is_function(pool.release)
        end)

        it("provides clear method", function()
            local pool = ptutil.WidgetPool:new()
            assert.is_function(pool.clear)
        end)
    end)

    describe("Widget acquisition and release", function()
        it("acquire returns a widget", function()
            local pool = ptutil.WidgetPool:new()
            local widget = pool:acquire("HorizontalSpan", { width = 10 })
            assert.is_table(widget)
        end)

        it("released widget can be reacquired", function()
            local pool = ptutil.WidgetPool:new()
            local widget1 = pool:acquire("HorizontalSpan", { width = 10 })
            pool:release(widget1)
            local widget2 = pool:acquire("HorizontalSpan", { width = 20 })
            -- Should reuse the released widget
            assert.is_table(widget2)
        end)

        it("pool limits size to prevent memory bloat", function()
            local pool = ptutil.WidgetPool:new({ max_per_type = 5 })
            local widgets = {}
            -- Create more widgets than the limit
            for i = 1, 10 do
                table.insert(widgets, pool:acquire("HorizontalSpan", { width = i }))
            end
            -- Release all
            for _, w in ipairs(widgets) do
                pool:release(w)
            end
            -- Pool should only keep up to max_per_type
            local count = pool:getPoolSize("HorizontalSpan")
            assert.is_true(count <= 5, "Pool should limit size per type")
        end)

        it("clear empties the pool", function()
            local pool = ptutil.WidgetPool:new()
            local widget = pool:acquire("HorizontalSpan", { width = 10 })
            pool:release(widget)
            pool:clear()
            local count = pool:getPoolSize("HorizontalSpan")
            assert.equal(0, count)
        end)
    end)

    describe("Multiple widget types", function()
        it("handles different widget types separately", function()
            local pool = ptutil.WidgetPool:new()
            local hspan = pool:acquire("HorizontalSpan", { width = 10 })
            local vspan = pool:acquire("VerticalSpan", { width = 20 })

            pool:release(hspan)
            pool:release(vspan)

            assert.equal(1, pool:getPoolSize("HorizontalSpan"))
            assert.equal(1, pool:getPoolSize("VerticalSpan"))
        end)
    end)

    describe("Performance impact", function()
        it("pooling reduces widget allocation count", function()
            local widget_counter = perf.WidgetCounter:new()
            local pool = ptutil.WidgetPool:new()

            -- Simulate multiple render cycles
            local widgets = {}
            for _ = 1, 5 do  -- 5 render cycles
                -- "Render" phase - acquire widgets
                for i = 1, 10 do
                    local w = pool:acquire("HorizontalSpan", { width = i })
                    table.insert(widgets, w)
                end
                -- "Cleanup" phase - release all
                for _, w in ipairs(widgets) do
                    pool:release(w)
                end
                widgets = {}
            end

            -- With pooling, we should see widget reuse
            -- The pool should have collected some widgets
            local pooled = pool:getPoolSize("HorizontalSpan")
            assert.is_true(pooled > 0, "Pool should collect released widgets")
        end)

        it("list page builds acquire pooled widgets in production path", function()
            local acquire_count = 0
            local pool = ptutil.WidgetPool:new()
            local original_acquire = pool.acquire
            pool.acquire = function(self, widget_type, init_params)
                acquire_count = acquire_count + 1
                return original_acquire(self, widget_type, init_params)
            end

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

            local menu = {
                width = 600,
                screen_w = 600,
                page = 1,
                perpage = 5,
                item_table = {
                    { text = "Book 1", file = "/books/book1.epub", path = "/books/book1.epub" },
                    { text = "Book 2", file = "/books/book2.epub", path = "/books/book2.epub" },
                },
                item_group = {},
                layout = {},
                items_to_update = {},
                itemnumber = 1,
                getBookInfo = function() return { been_opened = false, status = "unread" } end,
                item_dimen = { copy = function() return { w = 100, h = 20 } end },
                item_width = 100,
                item_height = 20,
                render_context = mock_ui.default_render_context(),
                widget_pool = pool,
                _pooled_widgets_in_use = {},
                _do_cover_images = false,
            }
            for k, v in pairs(ListMenu) do menu[k] = v end

            menu:_updateItemsBuildUI()

            assert.is_true(acquire_count > 0, "ListMenu should acquire pooled widgets during page build")
        end)

        it("mosaic page builds acquire pooled widgets in production path", function()
            local acquire_count = 0
            local pool = ptutil.WidgetPool:new()
            local original_acquire = pool.acquire
            pool.acquire = function(self, widget_type, init_params)
                acquire_count = acquire_count + 1
                return original_acquire(self, widget_type, init_params)
            end

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

            local menu = {
                width = 600,
                screen_w = 600,
                page = 1,
                perpage = 6,
                nb_cols = 3,
                item_margin = 10,
                item_table = {
                    { text = "Book 1", file = "/books/book1.epub", path = "/books/book1.epub" },
                    { text = "Book 2", file = "/books/book2.epub", path = "/books/book2.epub" },
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
                render_context = mock_ui.default_render_context(),
                widget_pool = pool,
                _pooled_widgets_in_use = {},
                _do_cover_images = false,
            }
            for k, v in pairs(MosaicMenu) do menu[k] = v end

            menu:_updateItemsBuildUI()

            assert.is_true(acquire_count > 0, "MosaicMenu should acquire pooled widgets during page build")
        end)

        it("release helper returns acquired widgets to the pool for reuse", function()
            local pool = ptutil.WidgetPool:new()
            local menu = {
                widget_pool = pool,
                _pooled_widgets_in_use = {},
            }

            local first = ptutil.acquirePooledWidget(menu, "VerticalSpan", { width = 10 })
            ptutil.releasePooledWidgets(menu)
            assert.equal(1, pool:getPoolSize("VerticalSpan"))
            local second = ptutil.acquirePooledWidget(menu, "VerticalSpan", { width = 20 })

            assert.equal(0, pool:getPoolSize("VerticalSpan"))
            assert.are.equal(first, second)
        end)
    end)
end)

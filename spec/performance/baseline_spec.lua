--[[
    Performance Baseline Benchmarks

    This file establishes baseline performance measurements for the plugin.
    These tests document current performance and will fail if performance
    regresses significantly after optimizations.

    Run with: busted spec/performance/baseline_spec.lua
]]

local perf = require("spec.support.perf_helpers")
local mock_ui = require("spec.support.mock_ui")

describe("Performance Baselines", function()

    -- Store baseline measurements for comparison
    local baselines = {}

    setup(function()
        -- Set up all mocks before loading the modules under test
        mock_ui()

        -- Add additional mocks needed for covermenu
        package.loaded["ui/widget/booklist"] = {
            getBookInfo = function() return {} end,
            hasBookBeenOpened = function() return false end,
            getDocSettings = function() return {} end,
        }
        package.loaded["ui/widget/buttondialog"] = {
            new = function() return {} end
        }
        package.loaded["document/documentregistry"] = {
            hasProvider = function() return true end
        }
        package.loaded["ui/widget/filechooser"] = {
            getListItem = function() return {} end
        }
        package.loaded["ui/widget/infomessage"] = {
            new = function() return {} end
        }
        package.loaded["apps/filemanager/filemanagerbookinfo"] = {
            extendProps = function(props) return props end
        }
        package.loaded["apps/filemanager/filemanagerconverter"] = {
            isSupported = function() return false end
        }
        package.loaded["apps/filemanager/filemanagershortcuts"] = {
            hasFolderShortcut = function() return false end
        }
        package.loaded["apps/filemanager/filemanagermenu"] = {
            new = function() return {} end
        }
        package.loaded["ui/uimanager"] = {
            show = function() end,
            close = function() end,
            scheduleIn = function() end,
            unschedule = function() end,
            nextTick = function() end,
            setDirty = function() end,
        }
        package.loaded["titlebar"] = {
            new = function() return { dimen = { h = 50 } } end
        }

        -- Now we can safely require the actual modules
        -- Note: We load these after mock setup so they use mocked dependencies
    end)

    describe("Widget Allocation Tracking", function()
        local widget_counter
        local counted_widgets

        before_each(function()
            widget_counter = perf.WidgetCounter:new()

            -- Create counted versions of common widgets
            counted_widgets = {
                FrameContainer = perf.counted_mock_widget(widget_counter, "FrameContainer"),
                CenterContainer = perf.counted_mock_widget(widget_counter, "CenterContainer"),
                LeftContainer = perf.counted_mock_widget(widget_counter, "LeftContainer"),
                RightContainer = perf.counted_mock_widget(widget_counter, "RightContainer"),
                TopContainer = perf.counted_mock_widget(widget_counter, "TopContainer"),
                BottomContainer = perf.counted_mock_widget(widget_counter, "BottomContainer"),
                HorizontalGroup = perf.counted_mock_widget(widget_counter, "HorizontalGroup"),
                VerticalGroup = perf.counted_mock_widget(widget_counter, "VerticalGroup"),
                HorizontalSpan = perf.counted_mock_widget(widget_counter, "HorizontalSpan"),
                VerticalSpan = perf.counted_mock_widget(widget_counter, "VerticalSpan"),
                TextWidget = perf.counted_mock_widget(widget_counter, "TextWidget"),
                TextBoxWidget = perf.counted_mock_widget(widget_counter, "TextBoxWidget"),
                ImageWidget = perf.counted_mock_widget(widget_counter, "ImageWidget"),
                OverlapGroup = perf.counted_mock_widget(widget_counter, "OverlapGroup"),
                ProgressWidget = perf.counted_mock_widget(widget_counter, "ProgressWidget"),
            }

            -- Install counted widgets into package.loaded
            package.loaded["ui/widget/container/framecontainer"] = counted_widgets.FrameContainer
            package.loaded["ui/widget/container/centercontainer"] = counted_widgets.CenterContainer
            package.loaded["ui/widget/container/leftcontainer"] = counted_widgets.LeftContainer
            package.loaded["ui/widget/container/rightcontainer"] = counted_widgets.RightContainer
            package.loaded["ui/widget/container/topcontainer"] = counted_widgets.TopContainer
            package.loaded["ui/widget/container/bottomcontainer"] = counted_widgets.BottomContainer
            package.loaded["ui/widget/horizontalgroup"] = counted_widgets.HorizontalGroup
            package.loaded["ui/widget/verticalgroup"] = counted_widgets.VerticalGroup
            package.loaded["ui/widget/horizontalspan"] = counted_widgets.HorizontalSpan
            package.loaded["ui/widget/verticalspan"] = counted_widgets.VerticalSpan
            package.loaded["ui/widget/textwidget"] = counted_widgets.TextWidget
            package.loaded["ui/widget/textboxwidget"] = counted_widgets.TextBoxWidget
            package.loaded["ui/widget/imagewidget"] = counted_widgets.ImageWidget
            package.loaded["ui/widget/overlapgroup"] = counted_widgets.OverlapGroup
            package.loaded["ui/widget/progresswidget"] = counted_widgets.ProgressWidget

            -- Clear module cache so they reload with counted widgets
            package.loaded["mosaicmenu"] = nil
            package.loaded["listmenu"] = nil
        end)

        it("measures widget allocations for MosaicMenu page", function()
            local MosaicMenu = require("mosaicmenu")

            -- Create a minimal menu object with 9 items (3x3 grid)
            local item_table = {}
            for i = 1, 9 do
                table.insert(item_table, {
                    text = "Book " .. i,
                    file = "/books/book" .. i .. ".epub",
                    is_file = true,
                })
            end

            local menu = {
                inner_dimen = { w = 600, h = 800 },
                item_table = item_table,
                page = 1,
                perpage = 9,
                nb_cols = 3,  -- Used by _updateItemsBuildUI
                nb_rows = 3,
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
                item_group = {
                    clear = function() end,
                },
                layout = {},
                items_to_update = {},
                itemnumber = 1,
                recent_boundary_index = 0,
                getBookInfo = function() return {} end,
                render_context = mock_ui.default_render_context(),
                _has_cover_images = false,
                _do_cover_images = true,
                _do_center_partial_rows = true,
                no_refresh_covers = false,
                width = 600,
                screen_w = 600,
            }

            -- Mixin MosaicMenu methods
            for k, v in pairs(MosaicMenu) do
                if type(v) == "function" then
                    menu[k] = v
                end
            end

            widget_counter:reset()
            menu:_updateItemsBuildUI()

            local total = widget_counter:get_total()
            local counts = widget_counter:get_all_counts()

            -- Store for baseline documentation
            baselines.mosaic_widget_total = total
            baselines.mosaic_widget_counts = counts

            -- Document current performance (these are observations, not assertions yet)
            -- After optimization, we'll tighten these thresholds
            print("\n=== MosaicMenu Widget Allocation Baseline ===")
            print(string.format("Total widgets created: %d", total))
            for widget_type, count in pairs(counts) do
                print(string.format("  %s: %d", widget_type, count))
            end

            -- Soft assertion: should be under 300 widgets per page (current estimate)
            -- This will be tightened after optimization
            assert.is_true(total < 500,
                "Widget allocations should be reasonable, got " .. total)
        end)

        it("measures widget allocations for ListMenu page", function()
            local ListMenu = require("listmenu")

            -- Create a minimal menu object with 7 items
            local item_table = {}
            for i = 1, 7 do
                table.insert(item_table, {
                    text = "Book " .. i,
                    file = "/books/book" .. i .. ".epub",
                    is_file = true,
                })
            end

            local menu = {
                inner_dimen = { w = 600, h = 800 },
                item_table = item_table,
                page = 1,
                perpage = 7,
                files_per_page = 7,
                portrait_mode = true,
                item_width = 600,
                item_height = 100,
                item_dimen = {
                    w = 600, h = 100,
                    copy = function(self) return { w = self.w, h = self.h } end
                },
                item_group = {
                    clear = function() end,
                },
                layout = {},
                items_to_update = {},
                itemnumber = 1,
                recent_boundary_index = 0,
                getBookInfo = function() return {} end,
                render_context = mock_ui.default_render_context(),
                _has_cover_images = false,
                _do_cover_images = true,
                _do_hint_opened = true,
                _do_filename_only = false,
                no_refresh_covers = false,
                width = 600,
                screen_w = 600,
            }

            -- Mixin ListMenu methods
            for k, v in pairs(ListMenu) do
                if type(v) == "function" then
                    menu[k] = v
                end
            end

            widget_counter:reset()
            menu:_updateItemsBuildUI()

            local total = widget_counter:get_total()
            local counts = widget_counter:get_all_counts()

            baselines.list_widget_total = total
            baselines.list_widget_counts = counts

            print("\n=== ListMenu Widget Allocation Baseline ===")
            print(string.format("Total widgets created: %d", total))
            for widget_type, count in pairs(counts) do
                print(string.format("  %s: %d", widget_type, count))
            end

            assert.is_true(total < 500,
                "Widget allocations should be reasonable, got " .. total)
        end)
    end)

    describe("Database Query Tracking", function()
        local query_counter

        before_each(function()
            query_counter = perf.QueryCounter:new()

            -- Install query counter as the SQLite mock
            package.loaded["lua-ljsqlite3/init"] = {
                open = function()
                    return query_counter
                end
            }
        end)

        it("documents queries for folder cover generation", function()
            -- This test documents current query patterns
            -- After Phase 4/5 optimization, query count should drop significantly

            -- Simulate what getSubfolderCoverImages does
            query_counter:exec("SELECT directory, filename FROM bookinfo WHERE directory = '/books/' AND has_cover = 'Y' ORDER BY RANDOM() LIMIT 16")
            query_counter:exec("SELECT directory, filename FROM bookinfo WHERE directory LIKE '/books/%' AND has_cover = 'Y' ORDER BY RANDOM() LIMIT 16")

            local count = query_counter:get_count()

            print("\n=== Folder Cover Query Baseline ===")
            print(string.format("Queries per folder: %d", count))

            baselines.folder_cover_queries = count

            -- Current: 2 queries per folder (immediate + recursive)
            -- Target after optimization: 1 batch query for all folders on page
        end)
    end)

    describe("Settings Access Tracking", function()
        local call_counter
        local BookInfoManager

        before_each(function()
            call_counter = perf.CallCounter:new()

            -- Get the mock BookInfoManager
            BookInfoManager = package.loaded["bookinfomanager"]

            -- Wrap getSetting to count calls
            call_counter:wrap(BookInfoManager, "getSetting")
        end)

        after_each(function()
            call_counter:restore()
        end)

        it("documents getSetting calls during render context build", function()
            -- Load covermenu fresh
            package.loaded["covermenu"] = nil
            local CoverMenu = require("covermenu")

            call_counter:reset()

            -- Build render context (this is called once per page render)
            local context = CoverMenu.buildRenderContext({})

            local count = call_counter:get_count("getSetting")

            print("\n=== Render Context getSetting Baseline ===")
            print(string.format("getSetting calls: %d", count))

            baselines.render_context_getsetting_calls = count

            -- Currently should be ~12 calls (one per setting in buildRenderContext)
            -- This is acceptable - the issue is OTHER getSetting calls during rendering
            assert.is_true(count < 20,
                "Render context should make reasonable getSetting calls, got " .. count)
        end)
    end)

    describe("Memory Growth", function()
        it("measures memory stability over repeated page rebuilds", function()
            -- Reset mocks to use standard widgets
            mock_ui()
            package.loaded["mosaicmenu"] = nil

            local MosaicMenu = require("mosaicmenu")

            local item_table = {}
            for i = 1, 9 do
                table.insert(item_table, {
                    text = "Book " .. i,
                    file = "/books/book" .. i .. ".epub",
                    is_file = true,
                })
            end

            local menu = {
                inner_dimen = { w = 600, h = 800 },
                item_table = item_table,
                page = 1,
                perpage = 9,
                nb_cols = 3,
                nb_rows = 3,
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
                item_group = {
                    clear = function(self)
                        for i = 1, #self do self[i] = nil end
                    end,
                },
                layout = {},
                items_to_update = {},
                itemnumber = 1,
                recent_boundary_index = 0,
                getBookInfo = function() return {} end,
                render_context = mock_ui.default_render_context(),
                _has_cover_images = false,
                _do_cover_images = true,
                _do_center_partial_rows = true,
                no_refresh_covers = false,
                width = 600,
                screen_w = 600,
            }

            for k, v in pairs(MosaicMenu) do
                if type(v) == "function" then
                    menu[k] = v
                end
            end

            -- Warm up
            menu:_updateItemsBuildUI()

            -- Measure memory growth over 10 rebuilds
            local memory_delta = perf.measure_memory(function()
                for i = 1, 10 do
                    menu.item_group:clear()
                    menu.layout = {}
                    menu:_updateItemsBuildUI()
                end
            end)

            print("\n=== Memory Growth Baseline (10 rebuilds) ===")
            print(string.format("Memory growth: %.2f KB", memory_delta))

            baselines.memory_growth_10_rebuilds = memory_delta

            -- Should not grow excessively
            -- Target: under 500KB growth for 10 rebuilds
            assert.is_true(memory_delta < 2000,
                "Memory growth should be reasonable, got " .. memory_delta .. "KB")
        end)
    end)

    describe("Timing Baselines", function()
        it("measures MosaicMenu _updateItemsBuildUI time", function()
            mock_ui()
            package.loaded["mosaicmenu"] = nil

            local MosaicMenu = require("mosaicmenu")

            local item_table = {}
            for i = 1, 9 do
                table.insert(item_table, {
                    text = "Book " .. i,
                    file = "/books/book" .. i .. ".epub",
                    is_file = true,
                })
            end

            local menu = {
                inner_dimen = { w = 600, h = 800 },
                item_table = item_table,
                page = 1,
                perpage = 9,
                nb_cols = 3,
                nb_rows = 3,
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
                getBookInfo = function() return {} end,
                render_context = mock_ui.default_render_context(),
                _has_cover_images = false,
                _do_cover_images = true,
                _do_center_partial_rows = true,
                no_refresh_covers = false,
                width = 600,
                screen_w = 600,
            }

            for k, v in pairs(MosaicMenu) do
                if type(v) == "function" then
                    menu[k] = v
                end
            end

            -- Warm up
            menu:_updateItemsBuildUI()

            -- Measure average of 5 runs
            local total_time = 0
            for i = 1, 5 do
                menu.layout = {}
                local elapsed = perf.measure_time(function()
                    menu:_updateItemsBuildUI()
                end)
                total_time = total_time + elapsed
            end
            local avg_time = total_time / 5

            print("\n=== MosaicMenu Timing Baseline ===")
            print(string.format("Average _updateItemsBuildUI time: %.2f ms", avg_time))

            baselines.mosaic_build_time_ms = avg_time

            -- In test environment with mocks, should be very fast
            -- On real devices, this will be slower
            assert.is_true(avg_time < 100,
                "Build time should be reasonable, got " .. avg_time .. "ms")
        end)

        it("measures ListMenu _updateItemsBuildUI time", function()
            mock_ui()
            package.loaded["listmenu"] = nil

            local ListMenu = require("listmenu")

            local item_table = {}
            for i = 1, 7 do
                table.insert(item_table, {
                    text = "Book " .. i,
                    file = "/books/book" .. i .. ".epub",
                    is_file = true,
                })
            end

            local menu = {
                inner_dimen = { w = 600, h = 800 },
                item_table = item_table,
                page = 1,
                perpage = 7,
                files_per_page = 7,
                portrait_mode = true,
                item_width = 600,
                item_height = 100,
                item_dimen = {
                    w = 600, h = 100,
                    copy = function(self) return { w = self.w, h = self.h } end
                },
                item_group = { clear = function() end },
                layout = {},
                items_to_update = {},
                itemnumber = 1,
                recent_boundary_index = 0,
                getBookInfo = function() return {} end,
                render_context = mock_ui.default_render_context(),
                _has_cover_images = false,
                _do_cover_images = true,
                _do_hint_opened = true,
                _do_filename_only = false,
                no_refresh_covers = false,
                width = 600,
                screen_w = 600,
            }

            for k, v in pairs(ListMenu) do
                if type(v) == "function" then
                    menu[k] = v
                end
            end

            -- Warm up
            menu:_updateItemsBuildUI()

            -- Measure average of 5 runs
            local total_time = 0
            for i = 1, 5 do
                menu.layout = {}
                local elapsed = perf.measure_time(function()
                    menu:_updateItemsBuildUI()
                end)
                total_time = total_time + elapsed
            end
            local avg_time = total_time / 5

            print("\n=== ListMenu Timing Baseline ===")
            print(string.format("Average _updateItemsBuildUI time: %.2f ms", avg_time))

            baselines.list_build_time_ms = avg_time

            assert.is_true(avg_time < 100,
                "Build time should be reasonable, got " .. avg_time .. "ms")
        end)
    end)

    -- Print summary at end
    teardown(function()
        print("\n" .. string.rep("=", 60))
        print("PERFORMANCE BASELINE SUMMARY")
        print(string.rep("=", 60))
        for key, value in pairs(baselines) do
            if type(value) == "number" then
                print(string.format("  %s: %.2f", key, value))
            elseif type(value) == "table" then
                print(string.format("  %s: (table with %d entries)", key, 0))
            end
        end
        print(string.rep("=", 60))
    end)
end)

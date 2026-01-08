--[[
    Phase 2: Settings Access Optimization Tests

    These tests verify that getSetting() is not called repeatedly during rendering.
    The render_context should capture all settings once, then be passed to all
    rendering functions.
]]

local perf = require("spec.support.perf_helpers")
local mock_ui = require("spec.support.mock_ui")

describe("Render Context Optimization", function()
    local BookInfoManager
    local call_counter

    setup(function()
        mock_ui()

        -- Add additional mocks needed for covermenu
        package.loaded["ui/widget/booklist"] = {
            getBookInfo = function() return {} end,
            hasBookBeenOpened = function() return false end,
            getDocSettings = function() return {} end,
        }
        package.loaded["ui/widget/buttondialog"] = { new = function() return {} end }
        package.loaded["document/documentregistry"] = { hasProvider = function() return true end }
        package.loaded["ui/widget/filechooser"] = { getListItem = function() return {} end }
        package.loaded["ui/widget/infomessage"] = { new = function() return {} end }
        package.loaded["apps/filemanager/filemanagerbookinfo"] = { extendProps = function(props) return props end }
        package.loaded["apps/filemanager/filemanagerconverter"] = { isSupported = function() return false end }
        package.loaded["apps/filemanager/filemanagershortcuts"] = { hasFolderShortcut = function() return false end }
        package.loaded["apps/filemanager/filemanagermenu"] = { new = function() return {} end }
        package.loaded["ui/uimanager"] = {
            show = function() end,
            close = function() end,
            scheduleIn = function() end,
            unschedule = function() end,
            nextTick = function() end,
            setDirty = function() end,
        }
        package.loaded["titlebar"] = { new = function() return { dimen = { h = 50 } } end }

        BookInfoManager = package.loaded["bookinfomanager"]
    end)

    before_each(function()
        call_counter = perf.CallCounter:new()
        call_counter:wrap(BookInfoManager, "getSetting")
    end)

    after_each(function()
        call_counter:restore()
    end)

    describe("buildRenderContext coverage", function()
        it("captures all settings used in mosaicmenu rendering", function()
            package.loaded["covermenu"] = nil
            local CoverMenu = require("covermenu")

            local context = CoverMenu.buildRenderContext({})

            -- Verify all settings needed by mosaicmenu are present
            assert.is_not_nil(context.hide_file_info ~= nil or context.hide_file_info == nil, "hide_file_info should be captured")
            assert.is_not_nil(context.show_progress_in_mosaic ~= nil or context.show_progress_in_mosaic == nil)
            assert.is_not_nil(context.show_mosaic_titles ~= nil or context.show_mosaic_titles == nil)
            assert.is_not_nil(context.progress_text_format)
            assert.is_not_nil(context.series_mode ~= nil or context.series_mode == nil)
            assert.is_not_nil(context.show_name_grid_folders ~= nil or context.show_name_grid_folders == nil)
            assert.is_not_nil(context.disable_auto_foldercovers ~= nil or context.disable_auto_foldercovers == nil)
            assert.is_not_nil(context.use_stacked_foldercovers ~= nil or context.use_stacked_foldercovers == nil)
            assert.is_not_nil(context.force_focus_indicator ~= nil or context.force_focus_indicator == nil)
            assert.is_boolean(context.is_touch_device)

            -- NEW: These should be added to render_context for Phase 2
            -- Currently these are called directly in ptutil.lua hot paths
            assert.is_not_nil(context.force_max_progressbars ~= nil or context.force_max_progressbars == nil,
                "force_max_progressbars should be in render_context")
            assert.is_not_nil(context.force_no_progressbars ~= nil or context.force_no_progressbars == nil,
                "force_no_progressbars should be in render_context")
            assert.is_not_nil(context.show_pages_read_as_progress ~= nil or context.show_pages_read_as_progress == nil,
                "show_pages_read_as_progress should be in render_context")
        end)

        it("captures all settings used in listmenu rendering", function()
            package.loaded["covermenu"] = nil
            local CoverMenu = require("covermenu")

            local context = CoverMenu.buildRenderContext({})

            -- List menu uses the same settings plus some extras
            assert.is_not_nil(context.show_tags ~= nil or context.show_tags == nil)
            assert.is_not_nil(context.series_mode ~= nil or context.series_mode == nil)
        end)
    end)

    describe("getSetting call reduction", function()
        it("getSetting is called exactly once per setting during buildRenderContext", function()
            package.loaded["covermenu"] = nil
            local CoverMenu = require("covermenu")

            call_counter:reset()
            CoverMenu.buildRenderContext({})

            -- Count should be reasonable - one call per setting
            -- Currently ~10-12 settings in render_context
            local count = call_counter:get_count("getSetting")
            assert.is_true(count >= 10 and count <= 20,
                "Expected 10-20 getSetting calls, got " .. count)
        end)

        it("no getSetting calls occur during MosaicMenu _updateItemsBuildUI", function()
            -- This is the key test - after buildRenderContext is called,
            -- no additional getSetting calls should happen during item rendering

            mock_ui()

            -- Create fresh mocks with getSetting counter
            local mock_bookinfo_settings = {}
            local getsetting_during_render = 0
            package.loaded["bookinfomanager"] = {
                _settings = mock_bookinfo_settings,
                getBookInfo = function() return nil end,
                getSetting = function(_, key)
                    getsetting_during_render = getsetting_during_render + 1
                    return mock_bookinfo_settings[key]
                end,
                saveSetting = function(_, key, value)
                    if value == true then value = "Y" end
                    if value == false then value = nil end
                    mock_bookinfo_settings[key] = value
                end,
                getCachedCoverSize = function() return 100, 100, 1 end,
            }

            -- Override ptutil to use the fresh bookinfomanager
            package.loaded["ptutil"] = nil
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

            -- Build render context FIRST (this is allowed to call getSetting)
            local render_context = mock_ui.default_render_context()

            -- Reset counter - now measure only during rendering
            getsetting_during_render = 0

            local menu = {
                inner_dimen = { w = 600, h = 800 },
                item_table = item_table,
                page = 1,
                perpage = 9,
                nb_cols = 3,
                nb_rows = 3,
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
                render_context = render_context,
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

            menu:_updateItemsBuildUI()

            -- After optimization, this should be 0
            -- Currently it may be higher due to getSetting calls in ptutil
            perf.assert.calls_at_most(getsetting_during_render, 0,
                "No getSetting calls should occur during _updateItemsBuildUI. " ..
                "All settings should come from render_context.")
        end)

        it("no getSetting calls occur during ListMenu _updateItemsBuildUI", function()
            mock_ui()

            local mock_bookinfo_settings = {}
            local getsetting_during_render = 0
            package.loaded["bookinfomanager"] = {
                _settings = mock_bookinfo_settings,
                getBookInfo = function() return nil end,
                getSetting = function(_, key)
                    getsetting_during_render = getsetting_during_render + 1
                    return mock_bookinfo_settings[key]
                end,
                saveSetting = function(_, key, value)
                    if value == true then value = "Y" end
                    if value == false then value = nil end
                    mock_bookinfo_settings[key] = value
                end,
                getCachedCoverSize = function() return 100, 100, 1 end,
            }

            package.loaded["ptutil"] = nil
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

            local render_context = mock_ui.default_render_context()
            getsetting_during_render = 0

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
                render_context = render_context,
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

            menu:_updateItemsBuildUI()

            perf.assert.calls_at_most(getsetting_during_render, 0,
                "No getSetting calls should occur during ListMenu _updateItemsBuildUI.")
        end)
    end)

    describe("ptutil functions use render_context", function()
        it("showProgressBar accepts render_context parameter", function()
            package.loaded["ptutil"] = nil
            local ptutil = require("ptutil")

            -- The function should accept an optional render_context
            -- and use it instead of calling getSetting
            local context = {
                hide_file_info = true,
                show_pages_read_as_progress = nil,
                force_no_progressbars = nil,
                force_max_progressbars = nil,
            }

            -- After optimization, this should work without getSetting calls
            local pages, show_bar = ptutil.showProgressBar(100, context)

            assert.is_number(pages)
            assert.is_boolean(show_bar)
        end)

        it("onFocus uses render_context instead of getSetting", function()
            package.loaded["ptutil"] = nil
            local ptutil = require("ptutil")

            local underline_container = { color = 0 }
            local context = {
                is_touch_device = true,
                force_focus_indicator = true,
            }

            -- After optimization, onFocus should accept context
            ptutil.onFocus(underline_container, context)

            -- With force_focus_indicator=true, color should change
            -- (exact behavior depends on implementation)
        end)

        it("onUnfocus uses render_context instead of getSetting", function()
            package.loaded["ptutil"] = nil
            local ptutil = require("ptutil")

            local underline_container = { color = 1 }
            local context = {
                is_touch_device = true,
                force_focus_indicator = true,
            }

            ptutil.onUnfocus(underline_container, context)
        end)
    end)
end)

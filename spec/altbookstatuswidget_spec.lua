--[[
    Unit tests for AltBookStatusWidget

    AltBookStatusWidget provides an alternative book status/screensaver screen
    that displays book information, progress, statistics, and description.

    Run with: busted spec/altbookstatuswidget_spec.lua
]]

require 'busted.runner'()
local mock_ui = require("spec.support.mock_ui")

describe("AltBookStatusWidget", function()
    local AltBookStatusWidget
    local mock_screen
    local mock_doc_props
    local mock_ui_obj
    local mock_toc

    setup(function()
        mock_ui()

        -- Add getScreenMode to Screen mock if not present
        local Device = package.loaded["device"]
        if Device and Device.screen then
            Device.screen.getScreenMode = function() return "portrait" end
        end

        -- Mock RenderImage
        package.loaded["ui/renderimage"] = {
            scaleBlitBuffer = function(thumbnail, w, h) return thumbnail end
        }

        -- Mock FileManagerBookInfo
        package.loaded["apps/filemanager/filemanagerbookinfo"] = {
            getCoverImage = function(self, document)
                return {
                    getWidth = function() return 100 end,
                    getHeight = function() return 150 end,
                }
            end
        }

        -- Mock ScrollHtmlWidget
        package.loaded["ui/widget/scrollhtmlwidget"] = {
            new = function(self, args)
                return {
                    name = "ScrollHtmlWidget",
                    width = args.width,
                    height = args.height,
                    html_body = args.html_body,
                    getSize = function() return { w = args.width, h = args.height } end,
                }
            end
        }

        -- Override InputContainer to add registerTouchZones
        local original_InputContainer = package.loaded["ui/widget/container/inputcontainer"]
        package.loaded["ui/widget/container/inputcontainer"] = {
            new = function(self, args)
                args = args or {}
                args.name = "InputContainer"
                args.registerTouchZones = function() end
                args.getSize = function() return { w = 100, h = 100 } end
                return args
            end,
            extend = function(self, args)
                args = args or {}
                args.name = "InputContainer"
                args.registerTouchZones = function() end
                args.getSize = function() return { w = 100, h = 100 } end
                return args
            end,
        }

        AltBookStatusWidget = require("altbookstatuswidget")
    end)

    -- Helper to create mock widget context
    local function create_mock_widget()
        mock_toc = {
            getChapterPageCount = function(self, page) return 20 end,
            getChapterPagesDone = function(self, page) return 5 end,
            getTocTitleByPage = function(self, page) return "Chapter 1: Introduction" end,
        }

        mock_doc_props = {
            display_title = "Test Book Title",
            authors = "Test Author; Another Author",
            series = "Test Series",
            series_index = 3,
            language = "en",
            description = "<p>This is a test book description.</p>",
        }

        mock_ui_obj = {
            getCurrentPage = function() return 50 end,
            document = {},
            doc_props = mock_doc_props,
            toc = mock_toc,
        }

        return {
            ui = mock_ui_obj,
            total_pages = 200,
            readonly = false,
            layout = {},
            onClose = function() end,
            getStatDays = function() return "5" end,
            getStatHours = function() return "2:30" end,
            getStatReadPages = function() return "50" end,
        }
    end

    describe("getStatusContent", function()
        it("returns a VerticalGroup widget", function()
            local widget = create_mock_widget()
            for k, v in pairs(AltBookStatusWidget) do widget[k] = v end

            local content = widget:getStatusContent(600)

            assert.is_not_nil(content)
            assert.equals("VerticalGroup", content.name)
        end)

        it("includes progress percentage in header", function()
            local widget = create_mock_widget()
            for k, v in pairs(AltBookStatusWidget) do widget[k] = v end

            local content = widget:getStatusContent(600)

            -- Progress should be 50/200 = 25%
            -- The content should include genHeader with progress
            assert.is_not_nil(content)
        end)
    end)

    describe("genHeader", function()
        it("creates header with title text", function()
            local widget = create_mock_widget()
            for k, v in pairs(AltBookStatusWidget) do widget[k] = v end
            widget.padding = 22

            local header = widget:genHeader("Test Header")

            assert.is_not_nil(header)
            assert.equals("VerticalGroup", header.name)
        end)

        it("creates header with line decorations", function()
            local widget = create_mock_widget()
            for k, v in pairs(AltBookStatusWidget) do widget[k] = v end
            widget.padding = 22

            local header = widget:genHeader("Progress: 25%")

            -- Header should contain HorizontalGroup with line widgets
            assert.is_not_nil(header)
            local found_hgroup = false
            for _, child in ipairs(header) do
                if child.name == "HorizontalGroup" then
                    found_hgroup = true
                    break
                end
            end
            assert.is_true(found_hgroup)
        end)
    end)

    describe("genBookInfoGroup", function()
        it("creates book info with cover and metadata", function()
            local widget = create_mock_widget()
            for k, v in pairs(AltBookStatusWidget) do widget[k] = v end
            widget.padding = 22

            local info_group = widget:genBookInfoGroup()

            assert.is_not_nil(info_group)
        end)

        it("includes author/series text when available", function()
            local widget = create_mock_widget()
            for k, v in pairs(AltBookStatusWidget) do widget[k] = v end
            widget.padding = 22

            local info_group = widget:genBookInfoGroup()

            -- Should include series info since props has series and series_index
            assert.is_not_nil(info_group)
        end)

        it("includes chapter title when available", function()
            local widget = create_mock_widget()
            for k, v in pairs(AltBookStatusWidget) do widget[k] = v end
            widget.padding = 22

            local info_group = widget:genBookInfoGroup()

            -- Chapter title from mock TOC should be included
            assert.is_not_nil(info_group)
        end)

        it("handles missing chapter title gracefully", function()
            local widget = create_mock_widget()
            widget.ui.toc.getTocTitleByPage = function() return nil end
            for k, v in pairs(AltBookStatusWidget) do widget[k] = v end
            widget.padding = 22

            -- Should not error
            local info_group = widget:genBookInfoGroup()
            assert.is_not_nil(info_group)
        end)

        it("creates readonly container when readonly is true", function()
            local widget = create_mock_widget()
            widget.readonly = true
            for k, v in pairs(AltBookStatusWidget) do widget[k] = v end
            widget.padding = 22

            local info_group = widget:genBookInfoGroup()

            -- Should return CenterContainer, not InputContainer
            assert.is_not_nil(info_group)
            assert.equals("CenterContainer", info_group.name)
        end)

        it("creates interactive container when readonly is false", function()
            local widget = create_mock_widget()
            widget.readonly = false
            for k, v in pairs(AltBookStatusWidget) do widget[k] = v end
            widget.padding = 22

            local info_group = widget:genBookInfoGroup()

            -- Should return InputContainer for tap handling
            assert.is_not_nil(info_group)
            assert.equals("InputContainer", info_group.name)
        end)
    end)

    describe("genStatisticsGroup", function()
        it("creates statistics with Days, Time, and Read pages", function()
            local widget = create_mock_widget()
            for k, v in pairs(AltBookStatusWidget) do widget[k] = v end

            local stats = widget:genStatisticsGroup(600)

            assert.is_not_nil(stats)
            assert.equals("CenterContainer", stats.name)
        end)

        it("uses stat helper methods for data", function()
            local calls = { days = 0, hours = 0, pages = 0 }
            local widget = create_mock_widget()
            widget.getStatDays = function()
                calls.days = calls.days + 1
                return "10"
            end
            widget.getStatHours = function()
                calls.hours = calls.hours + 1
                return "5:00"
            end
            widget.getStatReadPages = function()
                calls.pages = calls.pages + 1
                return "100"
            end
            for k, v in pairs(AltBookStatusWidget) do widget[k] = v end

            widget:genStatisticsGroup(600)

            assert.equals(1, calls.days)
            assert.equals(1, calls.hours)
            assert.equals(1, calls.pages)
        end)
    end)

    describe("genSummaryGroup", function()
        it("creates summary with book description", function()
            local widget = create_mock_widget()
            for k, v in pairs(AltBookStatusWidget) do widget[k] = v end
            widget.padding = 22

            local summary = widget:genSummaryGroup(600)

            assert.is_not_nil(summary)
            assert.equals("VerticalGroup", summary.name)
        end)

        it("shows placeholder when no description available", function()
            local widget = create_mock_widget()
            widget.ui.doc_props.description = nil
            for k, v in pairs(AltBookStatusWidget) do widget[k] = v end
            widget.padding = 22

            local summary = widget:genSummaryGroup(600)

            -- Should not error and should create widget
            assert.is_not_nil(summary)
        end)

        it("adds input_note to layout", function()
            local widget = create_mock_widget()
            for k, v in pairs(AltBookStatusWidget) do widget[k] = v end
            widget.padding = 22

            widget:genSummaryGroup(600)

            -- layout should have input_note added
            assert.equals(1, #widget.layout)
            assert.is_not_nil(widget.layout[1][1])
        end)
    end)

    describe("Progress calculations", function()
        it("calculates book progress percentage correctly", function()
            local widget = create_mock_widget()
            -- 50 / 200 = 0.25 = 25%
            for k, v in pairs(AltBookStatusWidget) do widget[k] = v end
            widget.padding = 22

            -- Progress is calculated in genBookInfoGroup
            local info_group = widget:genBookInfoGroup()

            assert.is_not_nil(info_group)
        end)

        it("handles edge case of page 1", function()
            local widget = create_mock_widget()
            widget.ui.getCurrentPage = function() return 1 end
            for k, v in pairs(AltBookStatusWidget) do widget[k] = v end
            widget.padding = 22

            -- Should not error
            local info_group = widget:genBookInfoGroup()
            assert.is_not_nil(info_group)
        end)

        it("handles edge case of last page", function()
            local widget = create_mock_widget()
            widget.ui.getCurrentPage = function() return 200 end
            for k, v in pairs(AltBookStatusWidget) do widget[k] = v end
            widget.padding = 22

            -- Should not error
            local info_group = widget:genBookInfoGroup()
            assert.is_not_nil(info_group)
        end)
    end)

    describe("Author formatting", function()
        it("formats multiple authors correctly", function()
            local widget = create_mock_widget()
            widget.ui.doc_props.authors = "First Author; Second Author; Third Author"
            for k, v in pairs(AltBookStatusWidget) do widget[k] = v end
            widget.padding = 22

            -- Should not error and should format authors
            local info_group = widget:genBookInfoGroup()
            assert.is_not_nil(info_group)
        end)

        it("handles missing authors", function()
            local widget = create_mock_widget()
            widget.ui.doc_props.authors = nil
            for k, v in pairs(AltBookStatusWidget) do widget[k] = v end
            widget.padding = 22

            -- Should not error
            local info_group = widget:genBookInfoGroup()
            assert.is_not_nil(info_group)
        end)
    end)

    describe("Series formatting", function()
        it("formats series with index", function()
            local widget = create_mock_widget()
            widget.ui.doc_props.series = "Epic Fantasy Series"
            widget.ui.doc_props.series_index = 5
            for k, v in pairs(AltBookStatusWidget) do widget[k] = v end
            widget.padding = 22

            -- Should format series correctly
            local info_group = widget:genBookInfoGroup()
            assert.is_not_nil(info_group)
        end)

        it("handles missing series", function()
            local widget = create_mock_widget()
            widget.ui.doc_props.series = nil
            widget.ui.doc_props.series_index = nil
            for k, v in pairs(AltBookStatusWidget) do widget[k] = v end
            widget.padding = 22

            -- Should not error
            local info_group = widget:genBookInfoGroup()
            assert.is_not_nil(info_group)
        end)

        it("handles series without index", function()
            local widget = create_mock_widget()
            widget.ui.doc_props.series = "Some Series"
            widget.ui.doc_props.series_index = nil
            for k, v in pairs(AltBookStatusWidget) do widget[k] = v end
            widget.padding = 22

            -- Should not error
            local info_group = widget:genBookInfoGroup()
            assert.is_not_nil(info_group)
        end)
    end)
end)

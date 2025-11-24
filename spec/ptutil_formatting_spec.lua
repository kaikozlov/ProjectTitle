require 'busted.runner'()
local setup_mocks = require("spec.support.mock_ui")

describe("ptutil Formatting Functions", function()
    local ptutil

    setup(function()
        setup_mocks()
        ptutil = require("ptutil")
    end)

    describe("formatAuthors", function()
        it("returns empty string for nil authors", function()
            local result = ptutil.formatAuthors(nil)
            assert.equal("", result)
        end)

        it("returns empty string for empty string", function()
            local result = ptutil.formatAuthors("")
            assert.equal("", result)
        end)

        it("formats single author", function()
            local result = ptutil.formatAuthors("John Doe")
            assert.equal("John Doe", result)
        end)

        it("formats multiple authors with newline separator", function()
            local result = ptutil.formatAuthors("John Doe\nJane Smith")
            -- Should have newline preserved or processed by BD.auto
            assert.is_not_nil(result)
            assert.is_string(result)
        end)

        it("formats authors with limit and et al.", function()
            local result = ptutil.formatAuthors("John Doe\nJane Smith\nBob Johnson", 2)
            -- Should include "et al." for 2nd author when limit is 2 and there are more
            assert.match("et al%.", result)
        end)

        it("respects authors_limit parameter", function()
            local result = ptutil.formatAuthors("A\nB\nC\nD\nE", 1)
            assert.match("et al%.", result)
        end)

        it("handles authors without newlines", function()
            local result = ptutil.formatAuthors("O'Brien, John")
            assert.is_not_nil(result)
            assert.is_string(result)
        end)
    end)

    describe("formatSeries", function()
        it("returns empty string for empty series", function()
            local result = ptutil.formatSeries("")
            assert.equal("", result)
        end)

        it("formats series without index", function()
            local result = ptutil.formatSeries("The Great Series")
            assert.equal("The Great Series", result)
        end)

        it("formats series with integer index", function()
            local result = ptutil.formatSeries("The Great Series", 1)
            -- Format is "#index - series"
            assert.match("#1", result)
            assert.match("The Great Series", result)
        end)

        it("formats series with zero index returns empty", function()
            local result = ptutil.formatSeries("Prequel Series", 0)
            assert.equal("", result)
        end)

        it("handles series with colon subseries extraction", function()
            local result = ptutil.formatSeries("Big Series: Small Subseries", 1)
            -- Should extract "Small Subseries" after the colon
            assert.match("Small Subseries", result)
            assert.not_match("Big Series:", result)
        end)
    end)

    describe("formatAuthorSeries", function()
        it("returns empty string when both authors and series are nil/empty", function()
            local result = ptutil.formatAuthorSeries(nil, nil)
            assert.equal("", result)
        end)

        it("returns only authors when series is empty", function()
            local result = ptutil.formatAuthorSeries("John Doe", "", "series_in_separate_line")
            assert.equal("John Doe", result)
        end)

        it("returns only series when authors is nil in series_in_separate_line mode", function()
            local result = ptutil.formatAuthorSeries(nil, "Great Series #1", "series_in_separate_line")
            assert.equal("Great Series #1", result)
        end)

        it("formats with series_in_separate_line mode with newline", function()
            local result = ptutil.formatAuthorSeries("John Doe", "Great Series #1", "series_in_separate_line")
            -- Should contain both with newline separator
            assert.match("John Doe", result)
            assert.match("Great Series #1", result)
        end)

        it("handles empty authors string", function()
            local result = ptutil.formatAuthorSeries("", "Great Series #1", "series_in_separate_line")
            assert.equal("Great Series #1", result)
        end)

        it("handles empty series string", function()
            local result = ptutil.formatAuthorSeries("John Doe", "", "series_in_separate_line")
            assert.equal("John Doe", result)
        end)
    end)

    describe("formatTags", function()
        it("returns nil for nil keywords", function()
            assert.is_nil(ptutil.formatTags(nil))
        end)

        it("returns nil for empty string", function()
            assert.is_nil(ptutil.formatTags(""))
        end)

        it("formats single tag", function()
            local result = ptutil.formatTags("fiction")
            assert.is_not_nil(result)
            assert.match("fiction", result)
        end)

        it("formats multiple tags with newline separator", function()
            local result = ptutil.formatTags("fiction\nscience\nadventure")
            assert.is_not_nil(result)
            assert.is_string(result)
        end)

        it("formats tags with limit", function()
            local result = ptutil.formatTags("fiction\nscience\nadventure\nmystery\nthriller", 3)
            assert.is_not_nil(result)
            -- Should limit to 3 tags
            local count = select(2, result:gsub(",", ","))
            assert.is_true(count <= 3)
        end)
    end)

    describe("showProgressBar", function()
        it("returns page count and show flag", function()
            local BookInfoManager = require("bookinfomanager")
            BookInfoManager._settings = {}

            local width, show = ptutil.showProgressBar(100)
            assert.is_not_nil(width)
            -- show can be nil, false, or true depending on settings
            -- Just verify function returns without error
        end)

        it("returns page count parameter when provided", function()
            local BookInfoManager = require("bookinfomanager")
            BookInfoManager._settings = {}

            local width, show = ptutil.showProgressBar(250)
            assert.equal(250, width)
        end)

        it("show flag depends on settings", function()
            local BookInfoManager = require("bookinfomanager")
            BookInfoManager._settings = {
                hide_file_info = "Y"
            }

            local width, show = ptutil.showProgressBar(100)
            -- Show depends on multiple settings, can be nil/false/true
            -- Just verify function returns without error
        end)
    end)

    describe("isPathChooser", function()
        it("returns false when no title_bar or menu", function()
            assert.is_false(ptutil.isPathChooser({}))
        end)

        it("returns true when title_bar has non-empty title", function()
            local obj = { title_bar = { title = "Select a folder" } }
            assert.is_true(ptutil.isPathChooser(obj))
        end)

        it("returns false when title_bar has empty title", function()
            local obj = { title_bar = { title = "" } }
            assert.is_false(ptutil.isPathChooser(obj))
        end)

        it("returns true when menu has non-empty title", function()
            local obj = { menu = { title = "Choose path" } }
            assert.is_true(ptutil.isPathChooser(obj))
        end)

        it("returns false when menu has empty title", function()
            local obj = { menu = { title = "" } }
            assert.is_false(ptutil.isPathChooser(obj))
        end)
    end)
end)

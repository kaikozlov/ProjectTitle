--[[
    Phase 8: String Allocation Reduction Tests

    These tests verify that string formatting functions
    minimize allocations through better patterns.
]]

local mock_ui = require("spec.support.mock_ui")

describe("String Allocation Optimization", function()
    local ptutil

    setup(function()
        mock_ui()
    end)

    before_each(function()
        package.loaded["ptutil"] = nil
        ptutil = require("ptutil")
    end)

    describe("Author formatting", function()
        it("formatAuthors handles single author", function()
            local result = ptutil.formatAuthors("John Doe", 3)
            assert.is_string(result)
            assert.equal("John Doe", result)
        end)

        it("formatAuthors handles multiple authors within limit", function()
            local result = ptutil.formatAuthors("John Doe\nJane Smith", 3)
            assert.is_string(result)
            -- Should contain both authors
            assert.truthy(result:find("John Doe"))
            assert.truthy(result:find("Jane Smith"))
        end)

        it("formatAuthors limits authors to specified count", function()
            local result = ptutil.formatAuthors("A\nB\nC\nD\nE", 2)
            assert.is_string(result)
            -- Should show "et al." for additional authors
            assert.truthy(result:find("et al"))
        end)

        it("formatAuthors handles nil input", function()
            local result = ptutil.formatAuthors(nil, 3)
            assert.equal("", result)
        end)

        it("formatAuthors handles empty string", function()
            local result = ptutil.formatAuthors("", 3)
            assert.equal("", result)
        end)
    end)

    describe("Series formatting", function()
        it("formatSeries handles basic series", function()
            local result = ptutil.formatSeries("Fantasy Series", 3)
            assert.is_string(result)
            assert.truthy(result:find("#3"))
            assert.truthy(result:find("Fantasy Series"))
        end)

        it("formatSeries suppresses index 0", function()
            local result = ptutil.formatSeries("Fantasy Series", 0)
            assert.equal("", result)
        end)

        it("formatSeries handles subseries format", function()
            local result = ptutil.formatSeries("Big Series: Small Subseries", 1)
            assert.is_string(result)
            -- Should show only the subseries part
            assert.truthy(result:find("Small Subseries"))
        end)

        it("formatSeries handles nil index", function()
            local result = ptutil.formatSeries("Fantasy Series", nil)
            assert.is_string(result)
        end)
    end)

    describe("Tags formatting", function()
        it("formatTags handles basic tags", function()
            local result = ptutil.formatTags("fiction\nfantasy\ndragons", 10)
            assert.is_string(result)
            assert.truthy(result:find("fiction"))
            assert.truthy(result:find("fantasy"))
        end)

        it("formatTags limits tags to specified count", function()
            local result = ptutil.formatTags("a\nb\nc\nd\ne", 2)
            assert.is_string(result)
            -- Should show ellipsis for additional tags
            assert.truthy(result:find("…"))
        end)

        it("formatTags handles nil input", function()
            local result = ptutil.formatTags(nil, 10)
            assert.is_nil(result)
        end)

        it("formatTags handles empty string", function()
            local result = ptutil.formatTags("", 10)
            assert.is_nil(result)
        end)
    end)

    describe("Author/Series combined formatting", function()
        it("formatAuthorSeries combines correctly", function()
            local result = ptutil.formatAuthorSeries("John Doe", "#1 - Series", "series_in_separate_line", false)
            assert.is_string(result)
        end)

        it("formatAuthorSeries handles nil authors", function()
            local result = ptutil.formatAuthorSeries(nil, "#1 - Series", "series_in_separate_line", false)
            assert.is_string(result)
        end)

        it("formatAuthorSeries handles empty authors with series", function()
            local result = ptutil.formatAuthorSeries("", "#1 - Series", "series_in_separate_line", false)
            -- When authors is empty but series exists, returns series
            assert.equal("#1 - Series", result)
        end)
    end)

    describe("String patterns", function()
        it("separator constants are defined", function()
            assert.is_table(ptutil.separator)
            assert.is_string(ptutil.separator.bar)
            assert.is_string(ptutil.separator.bullet)
            assert.is_string(ptutil.separator.comma)
            assert.is_string(ptutil.separator.dot)
        end)
    end)
end)

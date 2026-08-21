--[[
    Stateless font-estimate compatibility tests

    Project: Title's production fitting path measures real KOReader widgets
    from the nominal size downward. These tests retain the user-patch helper
    API without claiming that mocked heuristic timings predict device speed.
]]

local mock_ui = require("spec.support.mock_ui")

describe("Stateless font-estimate compatibility", function()
    local ptutil

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
    end)

    before_each(function()
        package.loaded["ptutil"] = nil
        ptutil = require("ptutil")
    end)

    describe("Font size estimation", function()
        it("provides estimateFontSize function", function()
            assert.is_function(ptutil.estimateFontSize,
                "ptutil should have an estimateFontSize function")
        end)

        it("returns valid font size within min/max bounds", function()
            local size = ptutil.estimateFontSize({
                text = "Short Title",
                width = 200,
                height = 100,
                min_size = 10,
                max_size = 26,
            })

            assert.is_number(size)
            assert.is_true(size >= 10, "Size should be >= min")
            assert.is_true(size <= 26, "Size should be <= max")
        end)

        it("returns larger font for short text", function()
            local short_size = ptutil.estimateFontSize({
                text = "Hi",
                width = 200,
                height = 100,
                min_size = 10,
                max_size = 26,
            })

            local long_size = ptutil.estimateFontSize({
                text = "This Is A Very Long Book Title That Spans Multiple Lines",
                width = 200,
                height = 100,
                min_size = 10,
                max_size = 26,
            })

            assert.is_true(short_size >= long_size,
                "Short text should get larger or equal font size")
        end)

        it("returns smaller font for smaller dimensions", function()
            local large_area_size = ptutil.estimateFontSize({
                text = "Test Title",
                width = 400,
                height = 200,
                min_size = 10,
                max_size = 26,
            })

            local small_area_size = ptutil.estimateFontSize({
                text = "Test Title",
                width = 100,
                height = 50,
                min_size = 10,
                max_size = 26,
            })

            assert.is_true(large_area_size >= small_area_size,
                "Larger area should allow larger or equal font size")
        end)

        it("respects max_size constraint", function()
            local size = ptutil.estimateFontSize({
                text = "A",  -- Very short text
                width = 1000,  -- Large area
                height = 500,
                min_size = 10,
                max_size = 20,  -- Lower max
            })

            assert.equal(20, size, "Should not exceed max_size")
        end)

        it("respects min_size constraint", function()
            local size = ptutil.estimateFontSize({
                text = string.rep("Very Long Text ", 50),  -- Extremely long
                width = 50,  -- Tiny area
                height = 20,
                min_size = 12,
                max_size = 26,
            })

            assert.equal(12, size, "Should not go below min_size")
        end)
    end)

    describe("Stateless font size estimation", function()
        it("handles same-length text with different newline counts independently", function()
            local single_line = ptutil.estimateFontSize({
                text = "abcdefghi",
                width = 90,
                height = 40,
                min_size = 10,
                max_size = 26,
            })

            local multiline = ptutil.estimateFontSize({
                text = "abcd\nefgh",
                width = 90,
                height = 40,
                min_size = 10,
                max_size = 26,
            })

            assert.not_equal(single_line, multiline)
        end)

        it("keeps clearFontSizeCache as a compatibility no-op", function()
            assert.is_function(ptutil.clearFontSizeCache,
                "ptutil should have a clearFontSizeCache function")
            assert.has_no.errors(function()
                ptutil.clearFontSizeCache()
            end)
        end)

        it("does not retain title-specific cache state", function()
            local cache_count = get_upvalue_by_name(ptutil.clearFontSizeCache, "font_size_cache_count")
            assert.is_nil(cache_count)
        end)
    end)

    describe("Quick-fit detection", function()
        it("provides isTextQuickFit function for simple cases", function()
            -- For very short text that will definitely fit at max size,
            -- we can skip the sizing loop entirely
            assert.is_function(ptutil.isTextQuickFit,
                "ptutil should have isTextQuickFit for fast-path detection")
        end)

        it("returns true for short text in large area", function()
            local fits = ptutil.isTextQuickFit({
                text = "Hi",
                width = 200,
                height = 100,
                max_size = 26,
            })

            assert.is_true(fits, "Short text in large area should quick-fit")
        end)

        it("returns false for long text in small area", function()
            local fits = ptutil.isTextQuickFit({
                text = string.rep("Long Text ", 20),
                width = 50,
                height = 30,
                max_size = 26,
            })

            assert.is_false(fits, "Long text in small area should not quick-fit")
        end)
    end)
end)

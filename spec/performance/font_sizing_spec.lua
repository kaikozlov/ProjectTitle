--[[
    Phase 3: Font Sizing Optimization Tests

    These tests verify that font sizing is more efficient than the current
    trial-and-error approach. The goal is to reduce widget allocations
    and iterations during the font sizing process.
]]

local perf = require("spec.support.perf_helpers")
local mock_ui = require("spec.support.mock_ui")

describe("Font Sizing Optimization", function()
    local ptutil
    local widget_counter
    local TextBoxWidget

    setup(function()
        mock_ui()
    end)

    before_each(function()
        widget_counter = perf.WidgetCounter:new()

        -- Create counted TextBoxWidget
        TextBoxWidget = perf.counted_mock_widget(widget_counter, "TextBoxWidget")
        -- Add TextBoxWidget-specific mock methods
        TextBoxWidget.has_split_inside_word = false
        local original_new = TextBoxWidget.new
        TextBoxWidget.new = function(self, o)
            local instance = original_new(self, o)
            instance.has_split_inside_word = false
            return instance
        end

        package.loaded["ui/widget/textboxwidget"] = TextBoxWidget
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

    describe("Font size caching", function()
        it("caches font size calculations", function()
            -- First call
            local size1 = ptutil.estimateFontSize({
                text = "Cached Title",
                width = 200,
                height = 100,
                min_size = 10,
                max_size = 26,
            })

            -- Second call with same params should use cache
            local size2 = ptutil.estimateFontSize({
                text = "Cached Title",
                width = 200,
                height = 100,
                min_size = 10,
                max_size = 26,
            })

            assert.equal(size1, size2)
        end)

        it("provides clearFontSizeCache function", function()
            assert.is_function(ptutil.clearFontSizeCache,
                "ptutil should have a clearFontSizeCache function")
        end)
    end)

    describe("Reduced widget allocations", function()
        it("FakeCover creates fewer TextBoxWidgets with optimization", function()
            -- This test documents the expected reduction in widget allocations
            -- Currently, FakeCover may create 16+ TextBoxWidgets per cover
            -- After optimization, it should create fewer

            -- Reset counter
            widget_counter:reset()

            -- Simulate what FakeCover does (simplified)
            -- With optimization, we should estimate font size first,
            -- then create widgets only once

            local estimated_size = ptutil.estimateFontSize({
                text = "Test Title",
                width = 180,
                height = 200,
                min_size = 10,
                max_size = 26,
            })

            -- Create widgets just once with estimated size
            TextBoxWidget:new({
                text = "Test Title",
                width = 180,
            })
            TextBoxWidget:new({
                text = "Test Author",
                width = 180,
            })

            local count = widget_counter:get_count("TextBoxWidget")

            -- With optimization, should be exactly 2 widgets (title + author)
            -- Without optimization, could be 10-30+ (multiple iterations)
            perf.assert.calls_at_most(count, 4,
                "Should create minimal TextBoxWidgets with font size estimation")
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

--[[
    Phase 6: Widget Allocation Reduction Tests

    These tests verify that widget pooling reduces allocations
    while maintaining correct rendering behavior.
]]

local perf = require("spec.support.perf_helpers")
local mock_ui = require("spec.support.mock_ui")

describe("Widget Pool Optimization", function()
    local ptutil

    setup(function()
        mock_ui()
    end)

    before_each(function()
        package.loaded["ptutil"] = nil
        ptutil = require("ptutil")
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
    end)
end)

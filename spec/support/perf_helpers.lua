--[[
    Performance Testing Utilities for Project Title Plugin

    This module provides tools for measuring and asserting performance characteristics
    in unit tests. It follows TDD principles - these utilities are tested themselves.

    Usage:
        local perf = require("spec.support.perf_helpers")

        -- Measure execution time
        local elapsed_ms = perf.measure_time(function()
            -- code to measure
        end)

        -- Measure memory growth
        local memory_delta_kb = perf.measure_memory(function()
            -- code that allocates memory
        end)

        -- Count function calls
        local counter = perf.CallCounter:new()
        counter:wrap(module, "method_name")
        -- ... run code ...
        local count = counter:get_count("method_name")

        -- Query counting for database operations
        local db_counter = perf.QueryCounter:new()
        -- ... use db_counter as mock db connection ...
        local query_count = db_counter:get_count()
]]

local PerfHelpers = {}

--- Measure the execution time of a function
-- @param fn Function to measure
-- @return elapsed_ms Number of milliseconds the function took to execute
-- @return result The return value of the function (if any)
function PerfHelpers.measure_time(fn)
    if type(fn) ~= "function" then
        error("measure_time requires a function argument")
    end

    local start_time = os.clock()
    local result = fn()
    local end_time = os.clock()

    -- Convert seconds to milliseconds
    local elapsed_ms = (end_time - start_time) * 1000

    return elapsed_ms, result
end

--- Measure the memory allocation growth during function execution
-- @param fn Function to measure
-- @return memory_delta_kb Memory growth in kilobytes
-- @return result The return value of the function (if any)
function PerfHelpers.measure_memory(fn)
    if type(fn) ~= "function" then
        error("measure_memory requires a function argument")
    end

    -- Force garbage collection to get accurate baseline
    collectgarbage("collect")
    collectgarbage("collect")

    local before_kb = collectgarbage("count")
    local result = fn()

    -- Don't collect after - we want to see what was allocated
    local after_kb = collectgarbage("count")

    local memory_delta_kb = after_kb - before_kb

    return memory_delta_kb, result
end

--- CallCounter - tracks how many times functions are called
-- Wraps module methods to count invocations without changing behavior
local CallCounter = {}
CallCounter.__index = CallCounter

function CallCounter:new()
    local instance = {
        counts = {},
        originals = {},  -- Store original functions for restoration
        wrapped_modules = {}  -- Track which modules were wrapped
    }
    setmetatable(instance, self)
    return instance
end

--- Wrap a module method to count calls
-- @param module The module/table containing the method
-- @param method_name The name of the method to wrap
function CallCounter:wrap(module, method_name)
    if type(module) ~= "table" then
        error("wrap requires a table/module as first argument")
    end
    if type(method_name) ~= "string" then
        error("wrap requires a string method name as second argument")
    end
    if type(module[method_name]) ~= "function" then
        error("method '" .. method_name .. "' is not a function")
    end

    -- Store original for restoration
    local key = tostring(module) .. ":" .. method_name
    self.originals[key] = module[method_name]
    self.counts[method_name] = 0

    -- Track for cleanup
    table.insert(self.wrapped_modules, {module = module, method = method_name, key = key})

    -- Wrap the function
    local counter = self
    local original = module[method_name]
    module[method_name] = function(...)
        counter.counts[method_name] = counter.counts[method_name] + 1
        return original(...)
    end
end

--- Get the call count for a method
-- @param method_name The name of the method
-- @return count Number of times the method was called
function CallCounter:get_count(method_name)
    return self.counts[method_name] or 0
end

--- Get all call counts
-- @return counts Table of {method_name -> count}
function CallCounter:get_all_counts()
    local copy = {}
    for k, v in pairs(self.counts) do
        copy[k] = v
    end
    return copy
end

--- Reset all counts to zero
function CallCounter:reset()
    for method_name in pairs(self.counts) do
        self.counts[method_name] = 0
    end
end

--- Restore all wrapped methods to their originals
function CallCounter:restore()
    for _, wrap_info in ipairs(self.wrapped_modules) do
        wrap_info.module[wrap_info.method] = self.originals[wrap_info.key]
    end
    self.wrapped_modules = {}
    self.originals = {}
    self.counts = {}
end

PerfHelpers.CallCounter = CallCounter


--- QueryCounter - mock database connection that counts queries
-- Use this as a drop-in replacement for SQLite connections in tests
local QueryCounter = {}
QueryCounter.__index = QueryCounter

function QueryCounter:new(options)
    options = options or {}
    local instance = {
        query_count = 0,
        queries = {},  -- Store actual queries for inspection
        exec_results = options.exec_results or nil,  -- Custom results for exec()
        prepare_results = options.prepare_results or nil,  -- Custom results for prepare()
    }
    setmetatable(instance, self)
    return instance
end

--- Simulate exec() - counts as one query
function QueryCounter:exec(sql)
    self.query_count = self.query_count + 1
    table.insert(self.queries, {type = "exec", sql = sql})
    return self.exec_results
end

--- Simulate prepare() - counts as one query
function QueryCounter:prepare(sql)
    self.query_count = self.query_count + 1
    table.insert(self.queries, {type = "prepare", sql = sql})

    -- Return a mock statement object
    local stmt = {
        _sql = sql,
        _bound_values = {},
        bind = function(self, ...)
            self._bound_values = {...}
            return self
        end,
        step = function(self)
            return nil  -- No rows by default
        end,
        reset = function(self)
            return self
        end,
        clearbind = function(self)
            self._bound_values = {}
            return self
        end,
        close = function(self)
            return nil
        end,
        get_value = function(self, idx)
            return nil
        end,
        get_values = function(self)
            return {}
        end,
    }

    return stmt
end

--- Simulate set_busy_timeout()
function QueryCounter:set_busy_timeout(timeout)
    -- No-op for testing
end

--- Simulate close()
function QueryCounter:close()
    -- No-op for testing
end

--- Get the total query count
-- @return count Number of queries executed
function QueryCounter:get_count()
    return self.query_count
end

--- Get all recorded queries
-- @return queries Array of {type, sql} tables
function QueryCounter:get_queries()
    local copy = {}
    for i, q in ipairs(self.queries) do
        copy[i] = {type = q.type, sql = q.sql}
    end
    return copy
end

--- Reset the query counter
function QueryCounter:reset()
    self.query_count = 0
    self.queries = {}
end

PerfHelpers.QueryCounter = QueryCounter


--- WidgetCounter - counts widget allocations
-- Wraps mock_widget factory to count instantiations
local WidgetCounter = {}
WidgetCounter.__index = WidgetCounter

function WidgetCounter:new()
    local instance = {
        counts = {},
        total = 0
    }
    setmetatable(instance, self)
    return instance
end

--- Record a widget creation
-- @param widget_type The type of widget created (e.g., "FrameContainer")
function WidgetCounter:record(widget_type)
    self.counts[widget_type] = (self.counts[widget_type] or 0) + 1
    self.total = self.total + 1
end

--- Get count for a specific widget type
-- @param widget_type The type of widget
-- @return count Number of that widget type created
function WidgetCounter:get_count(widget_type)
    return self.counts[widget_type] or 0
end

--- Get total widget count
-- @return total Total number of widgets created
function WidgetCounter:get_total()
    return self.total
end

--- Get all counts by type
-- @return counts Table of {widget_type -> count}
function WidgetCounter:get_all_counts()
    local copy = {}
    for k, v in pairs(self.counts) do
        copy[k] = v
    end
    return copy
end

--- Reset all counts
function WidgetCounter:reset()
    self.counts = {}
    self.total = 0
end

PerfHelpers.WidgetCounter = WidgetCounter


--- Helper to create a mock widget factory with counting
-- @param widget_counter A WidgetCounter instance
-- @param widget_name The name of the widget type
-- @return A widget class that counts instantiations
function PerfHelpers.counted_mock_widget(widget_counter, widget_name)
    local Widget = {}
    Widget.__index = Widget

    function Widget:new(o)
        widget_counter:record(widget_name)
        o = o or {}
        setmetatable(o, self)
        o.name = widget_name
        o.children = {}
        for i, v in ipairs(o) do
            table.insert(o.children, v)
        end
        if o.init then o:init() end
        return o
    end

    function Widget:extend(o)
        o = o or {}
        setmetatable(o, self)
        o.__index = o
        return o
    end

    function Widget:getSize()
        return { w = self.width or self.w or 100, h = self.height or self.h or 20 }
    end

    function Widget:free() end
    function Widget:paintTo() end
    function Widget:getBaseline() return 15 end
    function Widget:getTextHeight() return 20 end
    function Widget:getLineHeight() return 20 end
    function Widget:isTruncated() return false end
    function Widget:resetLayout() end
    function Widget:clear()
        for _, child in ipairs(self.children or {}) do
            if child.free then child:free() end
        end
        self.children = {}
        -- Also clear numbered indices
        for i = 1, #self do
            self[i] = nil
        end
    end

    return Widget
end


--- Assert helpers for performance tests
PerfHelpers.assert = {}

--- Assert that execution time is under a threshold
-- @param elapsed_ms Measured time in milliseconds
-- @param max_ms Maximum allowed time
-- @param message Optional message
function PerfHelpers.assert.time_under(elapsed_ms, max_ms, message)
    message = message or ""
    assert(elapsed_ms < max_ms,
        string.format("Expected execution time < %dms, got %.2fms. %s", max_ms, elapsed_ms, message))
end

--- Assert that memory growth is under a threshold
-- @param memory_delta_kb Measured memory delta in KB
-- @param max_kb Maximum allowed memory growth
-- @param message Optional message
function PerfHelpers.assert.memory_under(memory_delta_kb, max_kb, message)
    message = message or ""
    assert(memory_delta_kb < max_kb,
        string.format("Expected memory growth < %dKB, got %.2fKB. %s", max_kb, memory_delta_kb, message))
end

--- Assert that call count is at most a value
-- @param actual Actual call count
-- @param max_count Maximum allowed calls
-- @param message Optional message
function PerfHelpers.assert.calls_at_most(actual, max_count, message)
    message = message or ""
    assert(actual <= max_count,
        string.format("Expected at most %d calls, got %d. %s", max_count, actual, message))
end

--- Assert that call count equals a value
-- @param actual Actual call count
-- @param expected Expected call count
-- @param message Optional message
function PerfHelpers.assert.calls_equal(actual, expected, message)
    message = message or ""
    assert(actual == expected,
        string.format("Expected exactly %d calls, got %d. %s", expected, actual, message))
end


return PerfHelpers

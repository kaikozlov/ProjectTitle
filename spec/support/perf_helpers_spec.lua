--[[
    Tests for Performance Helper Utilities

    These tests verify that our performance testing tools work correctly
    before we use them to test the actual plugin code.
]]

describe("PerfHelpers", function()
    local perf

    setup(function()
        perf = require("spec.support.perf_helpers")
    end)

    describe("measure_time", function()
        it("accurately measures elapsed time", function()
            local elapsed_ms = perf.measure_time(function()
                -- Simple loop to create measurable delay
                local sum = 0
                for i = 1, 100000 do
                    sum = sum + i
                end
                return sum
            end)

            -- Should be positive and measurable
            assert.is_true(elapsed_ms >= 0, "Elapsed time should be non-negative")
            assert.is_number(elapsed_ms)
        end)

        it("returns the function result as second return value", function()
            local elapsed_ms, result = perf.measure_time(function()
                return "test_result"
            end)

            assert.is_number(elapsed_ms)
            assert.equal("test_result", result)
        end)

        it("errors when given non-function", function()
            assert.has_error(function()
                perf.measure_time("not a function")
            end, "measure_time requires a function argument")
        end)

        it("handles functions that return nil", function()
            local elapsed_ms, result = perf.measure_time(function()
                local x = 1 + 1
            end)

            assert.is_number(elapsed_ms)
            assert.is_nil(result)
        end)
    end)

    describe("measure_memory", function()
        it("tracks memory allocation growth", function()
            local memory_delta_kb = perf.measure_memory(function()
                -- Allocate a large table to create measurable memory growth
                local big_table = {}
                for i = 1, 10000 do
                    big_table[i] = string.rep("x", 100)
                end
                return big_table
            end)

            -- Should show positive memory growth
            assert.is_number(memory_delta_kb)
            assert.is_true(memory_delta_kb > 0, "Should detect memory allocation")
        end)

        it("returns the function result as second return value", function()
            local memory_delta_kb, result = perf.measure_memory(function()
                return {value = 42}
            end)

            assert.is_number(memory_delta_kb)
            assert.is_table(result)
            assert.equal(42, result.value)
        end)

        it("errors when given non-function", function()
            assert.has_error(function()
                perf.measure_memory(123)
            end, "measure_memory requires a function argument")
        end)

        it("shows minimal growth for no-allocation functions", function()
            local memory_delta_kb = perf.measure_memory(function()
                local x = 1 + 1
                return x
            end)

            -- Should be small (under 10KB for simple arithmetic)
            assert.is_true(memory_delta_kb < 10,
                "Simple function should not allocate much memory, got " .. memory_delta_kb .. "KB")
        end)
    end)

    describe("CallCounter", function()
        it("counts function invocations", function()
            local counter = perf.CallCounter:new()

            local test_module = {
                my_method = function() return "result" end
            }

            counter:wrap(test_module, "my_method")

            -- Call the method multiple times
            test_module.my_method()
            test_module.my_method()
            test_module.my_method()

            assert.equal(3, counter:get_count("my_method"))
        end)

        it("preserves original function behavior", function()
            local counter = perf.CallCounter:new()

            local test_module = {
                add = function(a, b) return a + b end
            }

            counter:wrap(test_module, "add")

            local result = test_module.add(2, 3)
            assert.equal(5, result)
            assert.equal(1, counter:get_count("add"))
        end)

        it("tracks multiple methods independently", function()
            local counter = perf.CallCounter:new()

            local test_module = {
                method_a = function() end,
                method_b = function() end,
            }

            counter:wrap(test_module, "method_a")
            counter:wrap(test_module, "method_b")

            test_module.method_a()
            test_module.method_a()
            test_module.method_b()

            assert.equal(2, counter:get_count("method_a"))
            assert.equal(1, counter:get_count("method_b"))
        end)

        it("returns all counts", function()
            local counter = perf.CallCounter:new()

            local test_module = {
                foo = function() end,
                bar = function() end,
            }

            counter:wrap(test_module, "foo")
            counter:wrap(test_module, "bar")

            test_module.foo()
            test_module.bar()
            test_module.bar()

            local all_counts = counter:get_all_counts()
            assert.equal(1, all_counts.foo)
            assert.equal(2, all_counts.bar)
        end)

        it("resets counts to zero", function()
            local counter = perf.CallCounter:new()

            local test_module = {
                method = function() end
            }

            counter:wrap(test_module, "method")
            test_module.method()
            test_module.method()

            assert.equal(2, counter:get_count("method"))

            counter:reset()

            assert.equal(0, counter:get_count("method"))
        end)

        it("restores original methods", function()
            local counter = perf.CallCounter:new()
            local original_fn = function() return "original" end

            local test_module = {
                method = original_fn
            }

            counter:wrap(test_module, "method")

            -- Wrapped version should still work
            assert.equal("original", test_module.method())

            -- After restore, should be back to original
            counter:restore()

            -- The function reference should be the original
            assert.equal(original_fn, test_module.method)
        end)

        it("returns 0 for unwrapped methods", function()
            local counter = perf.CallCounter:new()
            assert.equal(0, counter:get_count("nonexistent"))
        end)

        it("errors on invalid arguments", function()
            local counter = perf.CallCounter:new()

            assert.has_error(function()
                counter:wrap("not a table", "method")
            end, "wrap requires a table/module as first argument")

            assert.has_error(function()
                counter:wrap({}, 123)
            end, "wrap requires a string method name as second argument")

            assert.has_error(function()
                counter:wrap({not_a_function = "string"}, "not_a_function")
            end, "method 'not_a_function' is not a function")
        end)
    end)

    describe("QueryCounter", function()
        it("captures database query counts", function()
            local db = perf.QueryCounter:new()

            db:exec("SELECT * FROM books")
            db:exec("INSERT INTO books VALUES (1, 'Title')")

            assert.equal(2, db:get_count())
        end)

        it("counts prepare() calls", function()
            local db = perf.QueryCounter:new()

            local stmt = db:prepare("SELECT * FROM books WHERE id = ?")
            stmt:bind(1)
            stmt:step()

            assert.equal(1, db:get_count())
        end)

        it("records actual SQL queries", function()
            local db = perf.QueryCounter:new()

            db:exec("SELECT * FROM table1")
            db:prepare("SELECT * FROM table2 WHERE x = ?")

            local queries = db:get_queries()
            assert.equal(2, #queries)
            assert.equal("exec", queries[1].type)
            assert.equal("SELECT * FROM table1", queries[1].sql)
            assert.equal("prepare", queries[2].type)
            assert.equal("SELECT * FROM table2 WHERE x = ?", queries[2].sql)
        end)

        it("resets query count", function()
            local db = perf.QueryCounter:new()

            db:exec("SELECT 1")
            db:exec("SELECT 2")
            assert.equal(2, db:get_count())

            db:reset()
            assert.equal(0, db:get_count())
            assert.equal(0, #db:get_queries())
        end)

        it("provides working mock statement object", function()
            local db = perf.QueryCounter:new()

            local stmt = db:prepare("SELECT * FROM books")

            -- These should all work without error
            stmt:bind(1, "value")
            stmt:step()
            stmt:reset()
            stmt:clearbind()
            stmt:get_value(1)
            stmt:get_values()
            stmt:close()
        end)

        it("supports set_busy_timeout and close", function()
            local db = perf.QueryCounter:new()

            -- These should work without error
            db:set_busy_timeout(5000)
            db:close()
        end)
    end)

    describe("WidgetCounter", function()
        it("counts widget allocations by type", function()
            local counter = perf.WidgetCounter:new()

            counter:record("FrameContainer")
            counter:record("FrameContainer")
            counter:record("TextWidget")

            assert.equal(2, counter:get_count("FrameContainer"))
            assert.equal(1, counter:get_count("TextWidget"))
        end)

        it("tracks total widget count", function()
            local counter = perf.WidgetCounter:new()

            counter:record("FrameContainer")
            counter:record("TextWidget")
            counter:record("ImageWidget")

            assert.equal(3, counter:get_total())
        end)

        it("returns all counts by type", function()
            local counter = perf.WidgetCounter:new()

            counter:record("A")
            counter:record("B")
            counter:record("B")

            local counts = counter:get_all_counts()
            assert.equal(1, counts.A)
            assert.equal(2, counts.B)
        end)

        it("resets all counts", function()
            local counter = perf.WidgetCounter:new()

            counter:record("Widget")
            counter:record("Widget")

            counter:reset()

            assert.equal(0, counter:get_count("Widget"))
            assert.equal(0, counter:get_total())
        end)

        it("returns 0 for unrecorded widget types", function()
            local counter = perf.WidgetCounter:new()
            assert.equal(0, counter:get_count("NonexistentWidget"))
        end)
    end)

    describe("counted_mock_widget", function()
        it("creates widget factory that counts instantiations", function()
            local counter = perf.WidgetCounter:new()
            local MockWidget = perf.counted_mock_widget(counter, "TestWidget")

            MockWidget:new({})
            MockWidget:new({})

            assert.equal(2, counter:get_count("TestWidget"))
        end)

        it("produces functional widget objects", function()
            local counter = perf.WidgetCounter:new()
            local MockWidget = perf.counted_mock_widget(counter, "TestWidget")

            local widget = MockWidget:new({width = 100, height = 50})

            assert.equal("TestWidget", widget.name)
            assert.same({w = 100, h = 50}, widget:getSize())
        end)

        it("handles child widgets", function()
            local counter = perf.WidgetCounter:new()
            local MockWidget = perf.counted_mock_widget(counter, "Container")

            local child1 = {name = "child1"}
            local child2 = {name = "child2"}
            local widget = MockWidget:new({child1, child2})

            assert.equal(2, #widget.children)
            assert.equal("child1", widget.children[1].name)
        end)
    end)

    describe("assert helpers", function()
        describe("time_under", function()
            it("passes when time is under threshold", function()
                assert.has_no.errors(function()
                    perf.assert.time_under(50, 100)
                end)
            end)

            it("fails when time exceeds threshold", function()
                assert.has_error(function()
                    perf.assert.time_under(150, 100)
                end)
            end)
        end)

        describe("memory_under", function()
            it("passes when memory is under threshold", function()
                assert.has_no.errors(function()
                    perf.assert.memory_under(50, 100)
                end)
            end)

            it("fails when memory exceeds threshold", function()
                assert.has_error(function()
                    perf.assert.memory_under(150, 100)
                end)
            end)
        end)

        describe("calls_at_most", function()
            it("passes when calls are at or under limit", function()
                assert.has_no.errors(function()
                    perf.assert.calls_at_most(5, 5)
                    perf.assert.calls_at_most(3, 5)
                end)
            end)

            it("fails when calls exceed limit", function()
                assert.has_error(function()
                    perf.assert.calls_at_most(6, 5)
                end)
            end)
        end)

        describe("calls_equal", function()
            it("passes when counts match", function()
                assert.has_no.errors(function()
                    perf.assert.calls_equal(5, 5)
                end)
            end)

            it("fails when counts differ", function()
                assert.has_error(function()
                    perf.assert.calls_equal(4, 5)
                end)
            end)
        end)
    end)
end)

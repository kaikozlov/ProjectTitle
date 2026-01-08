--[[
    Phase 7: O(1) LRU Cache Implementation Tests

    These tests verify that the LRU cache operations are efficient
    and correctly evict the least recently used items.
]]

local perf = require("spec.support.perf_helpers")
local mock_ui = require("spec.support.mock_ui")

describe("O(1) LRU Cache", function()
    local LRUCache

    setup(function()
        mock_ui()
    end)

    before_each(function()
        package.loaded["lru_cache"] = nil
        package.loaded["ptutil"] = nil
        local ptutil = require("ptutil")
        LRUCache = ptutil.LRUCache
    end)

    describe("LRUCache class", function()
        it("provides LRUCache class", function()
            assert.is_table(LRUCache,
                "ptutil should have LRUCache class")
        end)

        it("can be instantiated with max_size", function()
            local cache = LRUCache:new(10)
            assert.is_table(cache)
        end)

        it("provides get method", function()
            local cache = LRUCache:new(10)
            assert.is_function(cache.get)
        end)

        it("provides put method", function()
            local cache = LRUCache:new(10)
            assert.is_function(cache.put)
        end)

        it("provides invalidate method", function()
            local cache = LRUCache:new(10)
            assert.is_function(cache.invalidate)
        end)

        it("provides clear method", function()
            local cache = LRUCache:new(10)
            assert.is_function(cache.clear)
        end)
    end)

    describe("Basic operations", function()
        it("get returns nil for missing key", function()
            local cache = LRUCache:new(10)
            local result = cache:get("nonexistent")
            assert.is_nil(result)
        end)

        it("put then get returns stored value", function()
            local cache = LRUCache:new(10)
            cache:put("key1", { data = "value1" })
            local result = cache:get("key1")
            assert.is_not_nil(result)
            assert.equal("value1", result.data)
        end)

        it("invalidate removes entry", function()
            local cache = LRUCache:new(10)
            cache:put("key1", { data = "value1" })
            cache:invalidate("key1")
            local result = cache:get("key1")
            assert.is_nil(result)
        end)

        it("clear removes all entries", function()
            local cache = LRUCache:new(10)
            cache:put("key1", { data = "value1" })
            cache:put("key2", { data = "value2" })
            cache:clear()
            assert.is_nil(cache:get("key1"))
            assert.is_nil(cache:get("key2"))
        end)
    end)

    describe("LRU eviction", function()
        it("maintains size limit", function()
            local cache = LRUCache:new(3)
            cache:put("key1", { data = 1 })
            cache:put("key2", { data = 2 })
            cache:put("key3", { data = 3 })
            cache:put("key4", { data = 4 })

            local size = cache:size()
            assert.equal(3, size)
        end)

        it("evicts least recently used item", function()
            local cache = LRUCache:new(3)
            cache:put("key1", { data = 1 })
            cache:put("key2", { data = 2 })
            cache:put("key3", { data = 3 })

            -- Adding 4th item should evict key1 (oldest)
            cache:put("key4", { data = 4 })

            assert.is_nil(cache:get("key1"))
            assert.is_not_nil(cache:get("key2"))
            assert.is_not_nil(cache:get("key3"))
            assert.is_not_nil(cache:get("key4"))
        end)

        it("get updates recency", function()
            local cache = LRUCache:new(3)
            cache:put("key1", { data = 1 })
            cache:put("key2", { data = 2 })
            cache:put("key3", { data = 3 })

            -- Access key1, making it most recent
            cache:get("key1")

            -- Adding 4th item should evict key2 (now oldest)
            cache:put("key4", { data = 4 })

            assert.is_not_nil(cache:get("key1"))  -- Still present
            assert.is_nil(cache:get("key2"))      -- Evicted
            assert.is_not_nil(cache:get("key3"))
            assert.is_not_nil(cache:get("key4"))
        end)

        it("put updates value for existing key", function()
            local cache = LRUCache:new(3)
            cache:put("key1", { data = 1 })
            cache:put("key1", { data = 100 })

            local result = cache:get("key1")
            assert.equal(100, result.data)

            -- Size should still be 1
            assert.equal(1, cache:size())
        end)
    end)

    describe("Performance characteristics", function()
        it("handles 1000 items without degradation", function()
            local cache = LRUCache:new(100)

            -- Insert 1000 items (many evictions)
            local start_time = os.clock()
            for i = 1, 1000 do
                cache:put("key" .. i, { data = i })
            end
            local elapsed = (os.clock() - start_time) * 1000

            -- Should complete quickly (O(1) per operation)
            assert.is_true(elapsed < 100,
                "1000 puts should complete in <100ms, took " .. elapsed .. "ms")
        end)

        it("get operation is fast", function()
            local cache = LRUCache:new(100)

            -- Pre-populate
            for i = 1, 100 do
                cache:put("key" .. i, { data = i })
            end

            -- Time 1000 gets
            local start_time = os.clock()
            for i = 1, 1000 do
                cache:get("key" .. (i % 100 + 1))
            end
            local elapsed = (os.clock() - start_time) * 1000

            -- Should complete quickly
            assert.is_true(elapsed < 50,
                "1000 gets should complete in <50ms, took " .. elapsed .. "ms")
        end)
    end)
end)

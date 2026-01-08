--[[
    Phase 4: Database Query Batching Tests

    These tests verify that book info can be fetched in batches
    rather than one query per file, reducing database round-trips.
]]

local perf = require("spec.support.perf_helpers")
local mock_ui = require("spec.support.mock_ui")

describe("Database Query Batching", function()
    local BookInfoManager
    local query_counter

    setup(function()
        mock_ui()

        -- Additional mocks needed for bookinfomanager.lua
        package.loaded["document/documentregistry"] = {
            hasProvider = function() return true end,
            getProvider = function() return {} end,
            openDocument = function() return nil end,
        }
        package.loaded["apps/filemanager/filemanagerbookinfo"] = {
            extendProps = function(props) return props or {} end,
            getCoverImage = function() return nil end,
        }
        package.loaded["ui/widget/infomessage"] = {
            new = function(self, o) return o end,
        }
        package.loaded["ui/renderimage"] = {
            scaleBlitBuffer = function(bb) return bb end,
        }
        package.loaded["ui/uimanager"] = {
            show = function() end,
            close = function() end,
            scheduleIn = function() end,
        }
        package.loaded["ffi/zstd"] = {
            zstd_uncompress_ctx = function() return nil, 0 end,
            zstd_compress = function() return nil, 0 end,
        }
        package.loaded["ui/time"] = {
            now = function() return 0 end,
            s = function(n) return n end,
        }

        -- Mock device with canUseWAL
        package.loaded["device"] = {
            screen = {
                scaleBySize = function(self, s) return s end,
                getWidth = function() return 600 end,
                getHeight = function() return 800 end,
            },
            isTouchDevice = function() return true end,
            canUseWAL = function() return false end,
            isAndroid = function() return false end,
            enableCPUCores = function() end,
        }

        -- Mock G_reader_settings
        _G.G_reader_settings = {
            readSetting = function() return nil end,
            isTrue = function() return false end,
            nilOrTrue = function() return false end,
        }
    end)

    before_each(function()
        query_counter = perf.QueryCounter:new()

        -- Install query counter as the SQLite mock
        package.loaded["lua-ljsqlite3/init"] = {
            open = function()
                return query_counter
            end
        }

        -- Clear and reload BookInfoManager
        package.loaded["bookinfomanager"] = nil
        BookInfoManager = require("bookinfomanager")
    end)

    describe("getBookInfoBatch", function()
        it("provides getBookInfoBatch function", function()
            assert.is_function(BookInfoManager.getBookInfoBatch,
                "BookInfoManager should have getBookInfoBatch method")
        end)

        it("returns a table mapping filepath to bookinfo", function()
            local filepaths = {
                "/books/book1.epub",
                "/books/book2.epub",
                "/books/book3.epub",
            }

            local results = BookInfoManager:getBookInfoBatch(filepaths, false)

            assert.is_table(results)
            -- Results should be indexed by filepath
            for _, path in ipairs(filepaths) do
                -- May be nil if not in DB, but key lookup should work
                local _ = results[path]
            end
        end)

        it("uses fewer queries than individual getBookInfo calls", function()
            local filepaths = {
                "/books/book1.epub",
                "/books/book2.epub",
                "/books/book3.epub",
                "/books/book4.epub",
                "/books/book5.epub",
            }

            -- Warm up DB connection (first call includes DB setup)
            BookInfoManager:getBookInfoBatch({"/warmup/book.epub"}, false)

            query_counter:reset()

            -- Batch query should use 1-2 queries max
            BookInfoManager:getBookInfoBatch(filepaths, false)

            local batch_count = query_counter:get_count()

            -- Should be much less than 5 (one per file)
            -- Expect 1 query for the batch select
            perf.assert.calls_at_most(batch_count, 3,
                "Batch query should use at most 3 DB operations, got " .. batch_count)
        end)

        it("handles empty filepath list", function()
            local results = BookInfoManager:getBookInfoBatch({}, false)

            assert.is_table(results)
            assert.equal(0, #results)
        end)

        it("handles filepaths not in database gracefully", function()
            local filepaths = {
                "/nonexistent/book1.epub",
                "/nonexistent/book2.epub",
            }

            local results = BookInfoManager:getBookInfoBatch(filepaths, false)

            assert.is_table(results)
            -- Missing entries should be nil
            assert.is_nil(results["/nonexistent/book1.epub"])
        end)

        it("properly escapes special characters in paths", function()
            local filepaths = {
                "/books/book's name.epub",
                "/books/book\"quoted\".epub",
                "/books/path;with;semicolons.epub",
            }

            -- Should not error
            assert.has_no.errors(function()
                BookInfoManager:getBookInfoBatch(filepaths, false)
            end)
        end)
    end)

    describe("Query efficiency", function()
        it("batch of 9 items uses at most 3 queries", function()
            local filepaths = {}
            for i = 1, 9 do
                table.insert(filepaths, "/books/book" .. i .. ".epub")
            end

            -- Warm up DB connection (first call includes DB setup)
            BookInfoManager:getBookInfoBatch({"/warmup/book.epub"}, false)

            query_counter:reset()
            BookInfoManager:getBookInfoBatch(filepaths, false)

            local count = query_counter:get_count()
            perf.assert.calls_at_most(count, 3,
                "9-item batch should use at most 3 queries")
        end)

        it("reuses existing database connection", function()
            -- First call opens connection
            BookInfoManager:getBookInfoBatch({"/books/book1.epub"}, false)

            local initial_count = query_counter:get_count()

            -- Second call should reuse connection (fewer setup queries)
            BookInfoManager:getBookInfoBatch({"/books/book2.epub"}, false)

            local second_count = query_counter:get_count() - initial_count

            -- Second call should be just the batch query
            perf.assert.calls_at_most(second_count, 2,
                "Subsequent batch should reuse connection")
        end)
    end)

    describe("Cover handling in batch", function()
        it("supports get_covers parameter", function()
            local filepaths = {"/books/book1.epub"}

            -- Should not error with get_covers = true
            assert.has_no.errors(function()
                BookInfoManager:getBookInfoBatch(filepaths, true)
            end)
        end)
    end)
end)

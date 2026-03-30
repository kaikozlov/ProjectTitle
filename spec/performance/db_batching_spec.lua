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

        it("prepares one combined statement for a 5-item metadata batch", function()
            local filepaths = {
                "/books/book1.epub",
                "/books/book2.epub",
                "/books/book3.epub",
                "/books/book4.epub",
                "/books/book5.epub",
            }
            local prepared_sql = {}
            local recording_conn = {
                exec = function() return nil end,
                prepare = function(self, sql)
                    table.insert(prepared_sql, sql)
                    return {
                        bind = function(self, ...) self._bound = { ... }; return self end,
                        step = function() return nil end,
                        reset = function(self) return self end,
                        clearbind = function(self) self._bound = {}; return self end,
                        close = function() end,
                        finalize = function() end,
                    }
                end,
                close = function() end,
                set_busy_timeout = function() end,
            }

            package.loaded["lua-ljsqlite3/init"] = {
                open = function() return recording_conn end
            }
            package.loaded["bookinfomanager"] = nil
            BookInfoManager = require("bookinfomanager")

            BookInfoManager:openDbConnection()
            prepared_sql = {}

            BookInfoManager:getBookInfoBatch(filepaths, false)

            assert.equal(1, #prepared_sql, "Batch lookup should prepare exactly one combined statement")
            assert.match("WHERE in_progress=0 AND %(%(", prepared_sql[1])
            assert.match("OR %(", prepared_sql[1])
            assert.not_match("cover_bb_type", prepared_sql[1])
            assert.not_match("cover_bb_stride", prepared_sql[1])
            assert.not_match("cover_bb_data", prepared_sql[1])
        end)

        it("filters out in-progress rows just like getBookInfo", function()
            local filepaths = {
                "/books/book1.epub",
                "/books/book2.epub",
            }
            local prepared_sql = {}
            local recording_conn = {
                exec = function() return nil end,
                prepare = function(self, sql)
                    table.insert(prepared_sql, sql)
                    return {
                        bind = function(self, ...) self._bound = { ... }; return self end,
                        step = function() return nil end,
                        reset = function(self) return self end,
                        clearbind = function(self) self._bound = {}; return self end,
                        close = function() end,
                        finalize = function() end,
                    }
                end,
                close = function() end,
                set_busy_timeout = function() end,
            }

            package.loaded["lua-ljsqlite3/init"] = {
                open = function() return recording_conn end
            }
            package.loaded["bookinfomanager"] = nil
            BookInfoManager = require("bookinfomanager")

            BookInfoManager:openDbConnection()
            prepared_sql = {}

            BookInfoManager:getBookInfoBatch(filepaths, false)

            assert.equal(1, #prepared_sql)
            assert.match("in_progress=0", prepared_sql[1])
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
            assert.is_true(results["/nonexistent/book1.epub"]._batch_miss)
        end)

        it("records explicit miss entries for queried filepaths with no row", function()
            local filepaths = {
                "/nonexistent/book1.epub",
                "/nonexistent/book2.epub",
            }

            local results = BookInfoManager:getBookInfoBatch(filepaths, false)

            assert.is_table(results["/nonexistent/book1.epub"])
            assert.is_true(results["/nonexistent/book1.epub"]._batch_miss)
            assert.is_table(results["/nonexistent/book2.epub"])
            assert.is_true(results["/nonexistent/book2.epub"]._batch_miss)
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
        it("prepares one combined statement for a 9-item metadata batch", function()
            local filepaths = {}
            for i = 1, 9 do
                table.insert(filepaths, "/books/book" .. i .. ".epub")
            end
            local prepared_sql = {}
            local recording_conn = {
                exec = function() return nil end,
                prepare = function(self, sql)
                    table.insert(prepared_sql, sql)
                    return {
                        bind = function(self, ...) self._bound = { ... }; return self end,
                        step = function() return nil end,
                        reset = function(self) return self end,
                        clearbind = function(self) self._bound = {}; return self end,
                        close = function() end,
                        finalize = function() end,
                    }
                end,
                close = function() end,
                set_busy_timeout = function() end,
            }

            package.loaded["lua-ljsqlite3/init"] = {
                open = function() return recording_conn end
            }
            package.loaded["bookinfomanager"] = nil
            BookInfoManager = require("bookinfomanager")

            BookInfoManager:openDbConnection()
            prepared_sql = {}
            BookInfoManager:getBookInfoBatch(filepaths, false)

            assert.equal(1, #prepared_sql)
            local clause_count = 0
            for _ in prepared_sql[1]:gmatch("directory=%? AND filename=%?") do
                clause_count = clause_count + 1
            end
            assert.equal(9, clause_count)
        end)

        it("reuses existing database connection", function()
            local open_count = 0
            local prepare_count = 0
            local recording_conn = {
                exec = function() return nil end,
                prepare = function(self, sql)
                    prepare_count = prepare_count + 1
                    return {
                        bind = function(self, ...) self._bound = { ... }; return self end,
                        step = function() return nil end,
                        reset = function(self) return self end,
                        clearbind = function(self) self._bound = {}; return self end,
                        close = function() end,
                        finalize = function() end,
                    }
                end,
                close = function() end,
                set_busy_timeout = function() end,
            }

            package.loaded["lua-ljsqlite3/init"] = {
                open = function()
                    open_count = open_count + 1
                    return recording_conn
                end
            }
            package.loaded["bookinfomanager"] = nil
            BookInfoManager = require("bookinfomanager")

            BookInfoManager:getBookInfoBatch({ "/books/book1.epub" }, false)
            BookInfoManager:getBookInfoBatch({ "/books/book2.epub", "/books/book3.epub" }, false)

            assert.equal(2, open_count,
                "Expected one create/open cycle on first use and no extra opens for the second batch")
            assert.equal(8, prepare_count,
                "Expected 6 base prepared statements, including folder-cover queries, and 1 batch prepare per batch call")
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

        it("includes cover blob columns in cover-inclusive batch SQL", function()
            local filepaths = { "/books/book1.epub", "/books/book2.epub" }
            local prepared_sql = {}
            local recording_conn = {
                exec = function() return nil end,
                prepare = function(self, sql)
                    table.insert(prepared_sql, sql)
                    return {
                        bind = function(self, ...) self._bound = { ... }; return self end,
                        step = function() return nil end,
                        reset = function(self) return self end,
                        clearbind = function(self) self._bound = {}; return self end,
                        close = function() end,
                        finalize = function() end,
                    }
                end,
                close = function() end,
                set_busy_timeout = function() end,
            }

            package.loaded["lua-ljsqlite3/init"] = {
                open = function() return recording_conn end
            }
            package.loaded["bookinfomanager"] = nil
            BookInfoManager = require("bookinfomanager")

            BookInfoManager:openDbConnection()
            prepared_sql = {}

            BookInfoManager:getBookInfoBatch(filepaths, true)

            assert.equal(1, #prepared_sql)
            assert.match("cover_bb_type", prepared_sql[1])
            assert.match("cover_bb_stride", prepared_sql[1])
            assert.match("cover_bb_data", prepared_sql[1])
        end)
    end)
end)

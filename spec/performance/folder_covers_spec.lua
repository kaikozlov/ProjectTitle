--[[
    Phase 5: Folder Cover Generation Optimization Tests

    These tests verify that folder cover generation is efficient
    and reuses the BookInfoManager database connection.
]]

local perf = require("spec.support.perf_helpers")
local mock_ui = require("spec.support.mock_ui")

describe("Folder Cover Generation Optimization", function()
    local ptutil
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

        -- Clear and reload modules
        package.loaded["bookinfomanager"] = nil
        package.loaded["ptutil"] = nil
        BookInfoManager = require("bookinfomanager")
        ptutil = require("ptutil")
    end)

    describe("Folder cover cache", function()
        it("provides clearFolderCoverCache function", function()
            assert.is_function(ptutil.clearFolderCoverCache,
                "ptutil should have clearFolderCoverCache method")
        end)

        it("clearing cache doesn't cause errors", function()
            assert.has_no.errors(function()
                ptutil.clearFolderCoverCache()
            end)
        end)

        it("reuses cached folder-cover data on repeated renders", function()
            local query_calls = 0
            local original_query_cover_paths = ptutil.query_cover_paths
            local original_getBookInfo = BookInfoManager.getBookInfo
            local original_getSetting = BookInfoManager.getSetting
            local original_directory_exists = package.loaded["util"].directoryExists
            local original_file_exists = package.loaded["util"].fileExists

            package.loaded["util"].directoryExists = function(path)
                return path == "/books/folder"
            end
            package.loaded["util"].fileExists = function(path)
                return path:match("^/books/folder/")
            end
            ptutil.query_cover_paths = function(folder, include_subfolders)
                query_calls = query_calls + 1
                return {
                    { "/books/folder/", "/books/folder/", "/books/folder/", "/books/folder/" },
                    { "a.epub", "b.epub", "c.epub", "d.epub" },
                }
            end
            BookInfoManager.getBookInfo = function(self, filepath, get_cover)
                return {
                    cover_w = 100,
                    cover_h = 150,
                    cover_bb = { filepath = filepath },
                    has_cover = "Y",
                }
            end
            BookInfoManager.getSetting = function(self, key)
                if key == "use_stacked_foldercovers" then
                    return nil
                end
                return nil
            end

            ptutil.clearFolderCoverCache()
            local first = ptutil.getSubfolderCoverImages("/books/folder", 100, 100)
            local second = ptutil.getSubfolderCoverImages("/books/folder", 100, 100)

            ptutil.query_cover_paths = original_query_cover_paths
            BookInfoManager.getBookInfo = original_getBookInfo
            BookInfoManager.getSetting = original_getSetting
            package.loaded["util"].directoryExists = original_directory_exists
            package.loaded["util"].fileExists = original_file_exists

            assert.is_not_nil(first)
            assert.is_not_nil(second)
            assert.equal(1, query_calls)
        end)
    end)

    describe("Query construction", function()
        it("uses a prepared subtree query with escaped LIKE wildcards", function()
            local prepared_sql
            local bound_values
            local exec_calls = 0
            local recording_conn = {
                exec = function()
                    exec_calls = exec_calls + 1
                    return nil
                end,
                prepare = function(self, sql)
                    prepared_sql = sql
                    return {
                        bind = function(self, ...)
                            bound_values = { ... }
                            return self
                        end,
                        step = function()
                            return nil
                        end,
                        clearbind = function(self)
                            return self
                        end,
                        reset = function(self)
                            return self
                        end,
                        close = function() end,
                        finalize = function() end,
                    }
                end,
            }

            BookInfoManager.openDbConnection = function(self)
                self.db_conn = recording_conn
            end
            BookInfoManager.db_conn = recording_conn
            package.loaded["util"].directoryExists = function(path)
                return path == "/books/100%_semi;quote'"
            end

            ptutil.query_cover_paths("/books/100%_semi;quote'", true)

            assert.equal(0, exec_calls)
            assert.match("LIKE %?", prepared_sql)
            assert.match("ESCAPE", prepared_sql)
            assert.equal("/books/100\\%\\_semi;quote'/%", bound_values[1])
        end)
    end)

    describe("Database connection reuse", function()
        it("clearing the cache forces the next folder-cover render to query again", function()
            local query_calls = 0
            local original_query_cover_paths = ptutil.query_cover_paths
            local original_getBookInfo = BookInfoManager.getBookInfo
            local original_getSetting = BookInfoManager.getSetting
            local original_directory_exists = package.loaded["util"].directoryExists
            local original_file_exists = package.loaded["util"].fileExists

            package.loaded["util"].directoryExists = function(path)
                return path == "/books/folder"
            end
            package.loaded["util"].fileExists = function(path)
                return path:match("^/books/folder/")
            end
            ptutil.query_cover_paths = function(folder, include_subfolders)
                query_calls = query_calls + 1
                return {
                    { "/books/folder/", "/books/folder/", "/books/folder/", "/books/folder/" },
                    { "a.epub", "b.epub", "c.epub", "d.epub" },
                }
            end
            BookInfoManager.getBookInfo = function(self, filepath, get_cover)
                return {
                    cover_w = 100,
                    cover_h = 150,
                    cover_bb = { filepath = filepath },
                    has_cover = "Y",
                }
            end
            BookInfoManager.getSetting = function() return nil end

            ptutil.clearFolderCoverCache()
            ptutil.getSubfolderCoverImages("/books/folder", 100, 100)
            ptutil.clearFolderCoverCache()
            ptutil.getSubfolderCoverImages("/books/folder", 100, 100)

            ptutil.query_cover_paths = original_query_cover_paths
            BookInfoManager.getBookInfo = original_getBookInfo
            BookInfoManager.getSetting = original_getSetting
            package.loaded["util"].directoryExists = original_directory_exists
            package.loaded["util"].fileExists = original_file_exists

            assert.equal(2, query_calls)
        end)
    end)

    describe("Efficient folder cover generation", function()
        it("getSubfolderCoverImages handles nil filepath gracefully", function()
            local result = ptutil.getSubfolderCoverImages(nil, 100, 100)
            assert.is_nil(result)
        end)

        it("getFolderCover handles nil filepath gracefully", function()
            local result = ptutil.getFolderCover(nil, 100, 100)
            assert.is_nil(result)
        end)

        it("getSubfolderCoverImages handles empty path gracefully", function()
            local result = ptutil.getSubfolderCoverImages("", 100, 100)
            assert.is_nil(result)
        end)
    end)

    describe("Performance characteristics", function()
        it("folder cover cache can be cleared multiple times", function()
            -- Should not error or leak memory
            for _ = 1, 10 do
                ptutil.clearFolderCoverCache()
            end
        end)
    end)
end)

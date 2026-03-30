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
            local original_getBookInfoBatch = BookInfoManager.getBookInfoBatch
            local original_getSetting = BookInfoManager.getSetting
            local original_directory_exists = package.loaded["util"].directoryExists
            local original_file_exists = package.loaded["util"].fileExists
            local original_split_file_path_name = package.loaded["util"].splitFilePathName

            package.loaded["util"].directoryExists = function(path)
                return path == "/books/folder"
            end
            package.loaded["util"].fileExists = function(path)
                return path:match("^/books/folder/")
            end
            package.loaded["util"].splitFilePathName = function(path)
                local directory, filename = path:match("^(.-)/([^/]+)$")
                return directory, filename
            end
            ptutil.query_cover_paths = function(folder, include_subfolders)
                query_calls = query_calls + 1
                return {
                    { "/books/folder/", "/books/folder/", "/books/folder/", "/books/folder/" },
                    { "a.epub", "b.epub", "c.epub", "d.epub" },
                }
            end
            BookInfoManager.getBookInfoBatch = function(self, filepaths, get_cover)
                local results = {}
                for _, filepath in ipairs(filepaths) do
                    results[filepath] = {
                        cover_w = 100,
                        cover_h = 150,
                        cover_bb = { filepath = filepath },
                        has_cover = "Y",
                    }
                end
                return results
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
            BookInfoManager.getBookInfoBatch = original_getBookInfoBatch
            BookInfoManager.getSetting = original_getSetting
            package.loaded["util"].directoryExists = original_directory_exists
            package.loaded["util"].fileExists = original_file_exists

            assert.is_not_nil(first)
            assert.is_not_nil(second)
            assert.equal(1, query_calls)
        end)

        it("rehydrates cached folder-cover selections from current book info on every render", function()
            local query_calls = 0
            local requested_filepaths = 0
            local original_query_cover_paths = ptutil.query_cover_paths
            local original_getBookInfoBatch = BookInfoManager.getBookInfoBatch
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
            BookInfoManager.getBookInfoBatch = function(self, filepaths, get_cover)
                requested_filepaths = requested_filepaths + #filepaths
                local results = {}
                for _, filepath in ipairs(filepaths) do
                    results[filepath] = {
                        cover_w = 100,
                        cover_h = 150,
                        cover_bb = { filepath = filepath, request = requested_filepaths },
                        has_cover = "Y",
                    }
                end
                return results
            end
            BookInfoManager.getSetting = function() return nil end

            ptutil.clearFolderCoverCache()
            ptutil.getSubfolderCoverImages("/books/folder", 100, 100)
            ptutil.getSubfolderCoverImages("/books/folder", 100, 100)

            ptutil.query_cover_paths = original_query_cover_paths
            BookInfoManager.getBookInfoBatch = original_getBookInfoBatch
            BookInfoManager.getSetting = original_getSetting
            package.loaded["util"].directoryExists = original_directory_exists
            package.loaded["util"].fileExists = original_file_exists

            assert.equal(1, query_calls)
            assert.equal(8, requested_filepaths)
        end)

        it("invalidates cached folder-cover selections after book-info updates", function()
            local query_calls = 0
            local original_query_cover_paths = ptutil.query_cover_paths
            local original_getBookInfoBatch = BookInfoManager.getBookInfoBatch
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
            BookInfoManager.getBookInfoBatch = function(self, filepaths, get_cover)
                local results = {}
                for _, filepath in ipairs(filepaths) do
                    results[filepath] = {
                        cover_w = 100,
                        cover_h = 150,
                        cover_bb = { filepath = filepath },
                        has_cover = "Y",
                    }
                end
                return results
            end
            BookInfoManager.getSetting = function() return nil end

            ptutil.clearFolderCoverCache()
            ptutil.getSubfolderCoverImages("/books/folder", 100, 100)
            BookInfoManager:setBookInfoProperties("/books/folder/a.epub", { ignore_cover = "Y" })
            ptutil.getSubfolderCoverImages("/books/folder", 100, 100)

            ptutil.query_cover_paths = original_query_cover_paths
            BookInfoManager.getBookInfoBatch = original_getBookInfoBatch
            BookInfoManager.getSetting = original_getSetting
            package.loaded["util"].directoryExists = original_directory_exists
            package.loaded["util"].fileExists = original_file_exists
            package.loaded["util"].splitFilePathName = original_split_file_path_name

            assert.equal(2, query_calls)
        end)

        it("keeps unrelated folder-cover selections cached after a single-book update", function()
            local query_calls = {
                ["/books/folder-one"] = 0,
                ["/books/folder-two"] = 0,
            }
            local original_query_cover_paths = ptutil.query_cover_paths
            local original_getBookInfoBatch = BookInfoManager.getBookInfoBatch
            local original_getSetting = BookInfoManager.getSetting
            local original_directory_exists = package.loaded["util"].directoryExists
            local original_file_exists = package.loaded["util"].fileExists
            local original_split_file_path_name = package.loaded["util"].splitFilePathName

            package.loaded["util"].directoryExists = function(path)
                return path == "/books/folder-one" or path == "/books/folder-two"
            end
            package.loaded["util"].fileExists = function(path)
                return path:match("^/books/folder%-one/") or path:match("^/books/folder%-two/")
            end
            package.loaded["util"].splitFilePathName = function(path)
                local directory, filename = path:match("^(.-)/([^/]+)$")
                return directory, filename
            end
            ptutil.query_cover_paths = function(folder, include_subfolders)
                query_calls[folder] = (query_calls[folder] or 0) + 1
                return {
                    { folder .. "/", folder .. "/", folder .. "/", folder .. "/" },
                    { "a.epub", "b.epub", "c.epub", "d.epub" },
                }
            end
            BookInfoManager.getBookInfoBatch = function(self, filepaths, get_cover)
                local results = {}
                for _, filepath in ipairs(filepaths) do
                    results[filepath] = {
                        cover_w = 100,
                        cover_h = 150,
                        cover_bb = { filepath = filepath },
                        has_cover = "Y",
                    }
                end
                return results
            end
            BookInfoManager.getSetting = function() return nil end

            ptutil.clearFolderCoverCache()
            ptutil.getSubfolderCoverImages("/books/folder-one", 100, 100)
            ptutil.getSubfolderCoverImages("/books/folder-two", 100, 100)
            BookInfoManager:setBookInfoProperties("/books/folder-one/a.epub", { ignore_cover = "Y" })
            ptutil.getSubfolderCoverImages("/books/folder-one", 100, 100)
            ptutil.getSubfolderCoverImages("/books/folder-two", 100, 100)

            ptutil.query_cover_paths = original_query_cover_paths
            BookInfoManager.getBookInfoBatch = original_getBookInfoBatch
            BookInfoManager.getSetting = original_getSetting
            package.loaded["util"].directoryExists = original_directory_exists
            package.loaded["util"].fileExists = original_file_exists
            package.loaded["util"].splitFilePathName = original_split_file_path_name

            assert.equal(2, query_calls["/books/folder-one"])
            assert.equal(1, query_calls["/books/folder-two"])
        end)

        it("hydrates folder-cover selections with getBookInfoBatch", function()
            local batch_calls = 0
            local original_query_cover_paths = ptutil.query_cover_paths
            local original_getBookInfo = BookInfoManager.getBookInfo
            local original_getBookInfoBatch = BookInfoManager.getBookInfoBatch
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
                return {
                    { "/books/folder/", "/books/folder/", "/books/folder/", "/books/folder/" },
                    { "a.epub", "b.epub", "c.epub", "d.epub" },
                }
            end
            BookInfoManager.getBookInfo = function()
                error("expected folder-cover hydration to use getBookInfoBatch")
            end
            BookInfoManager.getBookInfoBatch = function(self, filepaths, get_cover)
                batch_calls = batch_calls + 1
                local results = {}
                for _, filepath in ipairs(filepaths) do
                    results[filepath] = {
                        cover_w = 100,
                        cover_h = 150,
                        cover_bb = { filepath = filepath },
                        has_cover = "Y",
                    }
                end
                return results
            end
            BookInfoManager.getSetting = function() return nil end

            ptutil.clearFolderCoverCache()
            local result = ptutil.getSubfolderCoverImages("/books/folder", 100, 100)

            ptutil.query_cover_paths = original_query_cover_paths
            BookInfoManager.getBookInfo = original_getBookInfo
            BookInfoManager.getBookInfoBatch = original_getBookInfoBatch
            BookInfoManager.getSetting = original_getSetting
            package.loaded["util"].directoryExists = original_directory_exists
            package.loaded["util"].fileExists = original_file_exists

            assert.is_not_nil(result)
            assert.equal(1, batch_calls)
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
            local original_getBookInfoBatch = BookInfoManager.getBookInfoBatch
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
            BookInfoManager.getBookInfoBatch = function(self, filepaths, get_cover)
                local results = {}
                for _, filepath in ipairs(filepaths) do
                    results[filepath] = {
                        cover_w = 100,
                        cover_h = 150,
                        cover_bb = { filepath = filepath },
                        has_cover = "Y",
                    }
                end
                return results
            end
            BookInfoManager.getSetting = function() return nil end

            ptutil.clearFolderCoverCache()
            ptutil.getSubfolderCoverImages("/books/folder", 100, 100)
            ptutil.clearFolderCoverCache()
            ptutil.getSubfolderCoverImages("/books/folder", 100, 100)

            ptutil.query_cover_paths = original_query_cover_paths
            BookInfoManager.getBookInfoBatch = original_getBookInfoBatch
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

require 'busted.runner'()

describe("BookInfoManager", function()
    local BookInfoManager
    local queries = {}
    local mock_conn
    local folder_cache_clear_count = 0
    local folder_cache_invalidations = {}

    setup(function()
        -- Mock dependencies
        package.loaded["ui/bidi"] = {}
        package.loaded["ffi/blitbuffer"] = {}
        package.loaded["datastorage"] = {
            getSettingsDir = function() return "/tmp" end,
            getDataDir = function() return "/tmp" end
        }
        package.loaded["device"] = {
            screen = { width = 1024, height = 768 },
            canUseWAL = function() return true end
        }
        package.loaded["document/documentregistry"] = {}
        package.loaded["ffi/util"] = {
            template = function() end
        }
        package.loaded["apps/filemanager/filemanagerbookinfo"] = {}
        package.loaded["ui/widget/infomessage"] = {}
        package.loaded["ui/renderimage"] = {}
        
        -- Mock SQLite
        mock_conn = {
            exec = function(self, sql) 
                table.insert(queries, sql)
            end,
            prepare = function() return {
                bind = function() end,
                step = function() return nil end,
                reset = function() end,
                finalize = function() end,
                clearbind = function() return { reset = function() end } end
            } end,
            close = function() end,
            set_busy_timeout = function() end
        }
        package.loaded["lua-ljsqlite3/init"] = {
            open = function() return mock_conn end
        }
        
        package.loaded["ui/uimanager"] = {}
        package.loaded["apps/filemanager/filemanagerutil"] = {}
        package.loaded["libs/libkoreader-lfs"] = {
            attributes = function() return {} end
        }
        package.loaded["logger"] = {
            dbg = function() end,
            info = function() end,
            warn = function() end,
            err = function() end
        }
        package.loaded["util"] = {
            fileExists = function() return false end,
            splitFilePathName = function(path)
                local dir, file = path:match("^(.-)([^/]+)$")
                return dir or "", file or path
            end
        }
        package.loaded["ffi/zstd"] = {}
        package.loaded["ui/time"] = {
            s = function(val) return val end
        }
        
        -- Mock global G_reader_settings
        _G.G_reader_settings = {
            isTrue = function() return false end,
            saveSetting = function() end,
            has = function() return false end,
            readSetting = function() return nil end
        }
        
        -- Mock gettext
        local gettext_mock = {
            ngettext = function(s) return s end
        }
        setmetatable(gettext_mock, {
            __call = function(_, s) return s end
        })
        package.loaded["l10n.gettext"] = gettext_mock
        
        package.loaded["ptdbg"] = {}
        package.loaded["ptutil"] = {
            LRUCache = {
                new = function(_, max_size)
                    local store = {}
                    return {
                        get = function(_, key) return store[key] end,
                        put = function(_, key, value) store[key] = value end,
                        clear = function() store = {} end,
                        invalidate = function(_, key) store[key] = nil end,
                    }
                end
            },
            clearFolderCoverCache = function()
                folder_cache_clear_count = folder_cache_clear_count + 1
            end,
            invalidateFolderCoverCache = function(path)
                table.insert(folder_cache_invalidations, path)
            end,
        }

        -- Now require the module
        BookInfoManager = require("bookinfomanager")
    end)

    before_each(function()
        folder_cache_clear_count = 0
        folder_cache_invalidations = {}
    end)

    it("initializes and creates the table with correct schema", function()
        assert.is_not_nil(BookInfoManager)
        
        -- Trigger DB creation
        BookInfoManager:openDbConnection()
        
        -- Check if CREATE TABLE was called
        local create_table_called = false
        for _, sql in ipairs(queries) do
            if sql:match("CREATE TABLE IF NOT EXISTS bookinfo") then
                create_table_called = true
                -- Verify some columns exist
                assert.match("bcid%s+INTEGER PRIMARY KEY AUTOINCREMENT", sql)
                assert.match("directory%s+TEXT NOT NULL", sql)
                assert.match("filename%s+TEXT NOT NULL", sql)
                assert.match("filesize%s+INTEGER", sql)
                assert.match("filemtime%s+INTEGER", sql)
                assert.match("in_progress%s+INTEGER", sql)
                assert.match("unsupported%s+TEXT", sql)
                assert.match("cover_fetched%s+TEXT", sql)
                assert.match("has_meta%s+TEXT", sql)
                assert.match("has_cover%s+TEXT", sql)
                assert.match("cover_sizetag%s+TEXT", sql)
                assert.match("ignore_meta%s+TEXT", sql)
                assert.match("ignore_cover%s+TEXT", sql)
                assert.match("pages%s+INTEGER", sql)
                assert.match("title%s+TEXT", sql)
                assert.match("authors%s+TEXT", sql)
                assert.match("series%s+TEXT", sql)
                assert.match("series_index%s+REAL", sql)
                assert.match("language%s+TEXT", sql)
                assert.match("keywords%s+TEXT", sql)
                assert.match("description%s+TEXT", sql)
                assert.match("cover_w%s+INTEGER", sql)
                assert.match("cover_h%s+INTEGER", sql)
                assert.match("cover_bb_type%s+INTEGER", sql)
                assert.match("cover_bb_stride%s+INTEGER", sql)
                assert.match("cover_bb_data%s+BLOB", sql)
            end
        end
        assert.is_true(create_table_called, "CREATE TABLE bookinfo should have been executed")
    end)

    it("creates the config table", function()
        local create_config_called = false
        for _, sql in ipairs(queries) do
            if sql:match("CREATE TABLE IF NOT EXISTS config") then
                create_config_called = true
                assert.match("key%s+TEXT PRIMARY KEY", sql)
                assert.match("value%s+TEXT", sql)
            end
        end
        assert.is_true(create_config_called, "CREATE TABLE config should have been executed")
    end)

    it("creates the unique index", function()
        local create_index_called = false
        for _, sql in ipairs(queries) do
            if sql:match("CREATE UNIQUE INDEX IF NOT EXISTS dir_filename") then
                create_index_called = true
                assert.match("ON bookinfo%(directory, filename%)", sql)
            end
        end
        assert.is_true(create_index_called, "CREATE UNIQUE INDEX should have been executed")
    end)
    
    it("has the correct cache path", function()
        assert.is.equal("/tmp/PT_bookinfo_cache.sqlite3", BookInfoManager.db_location)
    end)

    describe("Settings", function()
        it("loads settings from DB", function()
            -- Mock exec to return data
            mock_conn.exec = function(self, sql)
                if sql:match("SELECT key, value FROM config") then
                    return {
                        {"some_key", "some_number"},
                        {"some_value", "123"}
                    }
                end
            end
            
            -- Mock lfs.attributes to return "file" so it proceeds
            package.loaded["libs/libkoreader-lfs"].attributes = function() return "file" end
            
            BookInfoManager:loadSettings()
            
            assert.is.equal("some_value", BookInfoManager.settings["some_key"])
            assert.is.equal(123, BookInfoManager.settings["some_number"])
        end)
        
        it("saves settings to DB", function()
            local bound_args = {}
            mock_conn.prepare = function(self, sql)
                if sql:match("INSERT OR REPLACE INTO config") then
                    return {
                        bind = function(self, ...) 
                            bound_args = {...}
                        end,
                        step = function() end,
                        clearbind = function() return { reset = function() end } end,
                        reset = function() end,
                        finalize = function() end
                    }
                end
                return {
                    bind = function() end,
                    step = function() end,
                    clearbind = function() return { reset = function() end } end,
                    reset = function() end,
                    finalize = function() end
                }
            end
            
            BookInfoManager:saveSetting("new_key", "new_val", nil, true)
            
            assert.is.equal("new_key", bound_args[1])
            assert.is.equal("new_val", bound_args[2])
        end)
    end)

    describe("Prepared statement selection", function()
        it("prepares separate metadata-only and cover-inclusive single-item selects", function()
            local prepared_sql = {}
            mock_conn.prepare = function(self, sql)
                table.insert(prepared_sql, sql)
                return {
                    bind = function() return nil end,
                    step = function() return nil end,
                    reset = function() end,
                    finalize = function() end,
                    clearbind = function()
                        return {
                            reset = function() end,
                        }
                    end,
                }
            end

            BookInfoManager.db_conn = nil
            BookInfoManager.db_created = true
            BookInfoManager:openDbConnection()

            local metadata_select_found = false
            local cover_select_found = false
            for _, sql in ipairs(prepared_sql) do
                if sql:match("SELECT") and sql:match("WHERE directory=%? AND filename=%? AND in_progress=0") then
                    if sql:match("cover_bb_data") then
                        cover_select_found = true
                    else
                        metadata_select_found = true
                    end
                end
            end

            assert.is_true(metadata_select_found)
            assert.is_true(cover_select_found)
        end)
    end)

    describe("Cover cache safety", function()
        it("stores a clone so later caller mutations do not poison the cache", function()
            local filepath = "/books/cache-safe.epub"
            local original = {
                has_cover = "Y",
                series = "Original Series",
                cover_bb = { id = 1 },
            }

            BookInfoManager:clearCoverCache()
            BookInfoManager:cacheCover(filepath, original)

            original.series = "Mutated Before Read"

            local cached_once = BookInfoManager:getCachedCover(filepath)
            cached_once.has_cover = nil
            cached_once.series = "Mutated After Read"

            local cached_twice = BookInfoManager:getCachedCover(filepath)

            assert.equal("Y", cached_twice.has_cover)
            assert.equal("Original Series", cached_twice.series)
            assert.are.same(original.cover_bb, cached_twice.cover_bb)
            assert.is_not.equal(cached_once, cached_twice)
        end)
    end)

    describe("Cover cache invalidation", function()
        it("invalidates cached cover on property updates", function()
            local invalidated = {}
            local filepath = "/books/update.epub"
            local original_invalidate = BookInfoManager.invalidateCachedCover

            BookInfoManager.invalidateCachedCover = function(self, path)
                table.insert(invalidated, path)
            end

            BookInfoManager:setBookInfoProperties(filepath, { ignore_cover = "Y" })

            BookInfoManager.invalidateCachedCover = original_invalidate

            assert.are.same({ filepath }, invalidated)
        end)

        it("invalidates cached cover on delete", function()
            local invalidated = {}
            local filepath = "/books/delete.epub"
            local original_invalidate = BookInfoManager.invalidateCachedCover

            BookInfoManager.invalidateCachedCover = function(self, path)
                table.insert(invalidated, path)
            end

            BookInfoManager:deleteBookInfo(filepath)

            BookInfoManager.invalidateCachedCover = original_invalidate

            assert.are.same({ filepath }, invalidated)
        end)

        it("clears cached covers when the database is emptied", function()
            local cleared = 0
            local original_clear = BookInfoManager.clearCoverCache

            BookInfoManager.clearCoverCache = function()
                cleared = cleared + 1
            end

            BookInfoManager:deleteDb()

            BookInfoManager.clearCoverCache = original_clear

            assert.equal(1, cleared)
        end)

        it("invalidates folder-cover caches for the changed path when invalidating one cached cover", function()
            BookInfoManager:invalidateCachedCover("/books/update.epub")

            assert.are.same({ "/books/update.epub" }, folder_cache_invalidations)
            assert.equal(0, folder_cache_clear_count)
        end)

        it("clears folder-cover cache when clearing all cached covers", function()
            BookInfoManager:clearCoverCache()

            assert.equal(1, folder_cache_clear_count)
        end)
    end)
end)

require 'busted.runner'()

describe("BookInfoManager", function()
    local BookInfoManager
    local queries = {}
    local mock_conn
    local folder_cache_clear_count = 0
    local folder_cache_invalidations = {}
    local created_cover_caches = {}

    setup(function()
        -- Mock dependencies
        package.loaded["ui/bidi"] = {}
        package.loaded["ffi/blitbuffer"] = {}
        package.loaded["ffi/archiver"] = {
            Reader = {
                new = function()
                    return {
                        open = function() return false end,
                        iterate = function()
                            return function() return nil end
                        end,
                        extractToMemory = function() return nil end,
                        close = function() end,
                    }
                end,
            },
        }
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
            directoryExists = function() return false end,
            splitFilePathName = function(path)
                local dir, file = path:match("^(.-)([^/]+)$")
                return dir or "", file or path
            end
        }
        package.loaded["ffi/zstd"] = {}
        package.loaded["ui/time"] = {
            s = function(val) return val end
        }
        package.loaded["cache"] = {
            new = function(_, opts)
                local used_size = 0
                local access_counter = 0
                local entries = {}
                local cache

                local function count_entries()
                    local count = 0
                    for _ in pairs(entries) do
                        count = count + 1
                    end
                    return count
                end

                local function evict_if_needed()
                    while used_size > opts.size do
                        local lru_key
                        local lru_stamp
                        for key, entry in pairs(entries) do
                            if not lru_stamp or entry.stamp < lru_stamp then
                                lru_key = key
                                lru_stamp = entry.stamp
                            end
                        end
                        if not lru_key then
                            break
                        end
                        used_size = used_size - entries[lru_key].size
                        entries[lru_key] = nil
                    end
                end

                cache = {
                    size = opts.size,
                    avg_itemsize = opts.avg_itemsize,
                    slots = math.ceil(opts.size / opts.avg_itemsize),
                    cache = {
                        get = function(_, key)
                            local entry = entries[key]
                            if not entry then
                                return nil
                            end
                            access_counter = access_counter + 1
                            entry.stamp = access_counter
                            return entry.value
                        end,
                        set = function(_, key, value, size)
                            local entry_size = size or 0
                            if entries[key] then
                                used_size = used_size - entries[key].size
                            end
                            access_counter = access_counter + 1
                            entries[key] = {
                                value = value,
                                size = entry_size,
                                stamp = access_counter,
                            }
                            used_size = used_size + entry_size
                            evict_if_needed()
                        end,
                        delete = function(_, key)
                            if entries[key] then
                                used_size = used_size - entries[key].size
                                entries[key] = nil
                            end
                        end,
                        clear = function()
                            entries = {}
                            used_size = 0
                        end,
                        used_size = function()
                            return used_size
                        end,
                        used_slots = function()
                            return count_entries()
                        end,
                    },
                    get = function(self, key)
                        return self.cache:get(key)
                    end,
                    check = function(self, key)
                        return self.cache:get(key)
                    end,
                    insert = function(self, key, value, size)
                        return self.cache:set(key, value, size)
                    end,
                    clear = function(self)
                        self.cache:clear()
                    end,
                }

                table.insert(created_cover_caches, cache)
                return cache
            end,
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
            escapeLikePattern = function(value)
                return tostring(value):gsub("\\", "\\\\"):gsub("%%", "\\%%"):gsub("_", "\\_")
            end,
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
        created_cover_caches = {}
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
        it("prepares separate exact-directory and subtree folder-cover selects", function()
            local prepared_sql = {}
            mock_conn.prepare = function(self, sql)
                table.insert(prepared_sql, sql)
                return {
                    bind = function(self, ...)
                        return self
                    end,
                    step = function()
                        return nil
                    end,
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

            local direct_select_found = false
            local subtree_select_found = false
            for _, sql in ipairs(prepared_sql) do
                if sql:match("SELECT directory, filename FROM bookinfo") and sql:match("has_cover = 'Y'") then
                    if sql:match("directory%s*=%?") then
                        direct_select_found = true
                    elseif sql:match("directory%s*>=%?") and sql:match("directory%s*<%?") then
                        subtree_select_found = true
                    end
                end
            end

            assert.is_true(direct_select_found)
            assert.is_true(subtree_select_found)
        end)

        it("excludes covers explicitly marked to be ignored from folder-cover candidates", function()
            local prepared_sql = {}
            mock_conn.prepare = function(self, sql)
                table.insert(prepared_sql, sql)
                return {
                    bind = function(self, ...)
                        return self
                    end,
                    step = function()
                        return nil
                    end,
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

            local folder_selects = 0
            for _, sql in ipairs(prepared_sql) do
                if sql:match("SELECT directory, filename FROM bookinfo") then
                    folder_selects = folder_selects + 1
                    assert.match("ignore_cover IS NULL", sql)
                end
            end
            assert.equal(2, folder_selects)
        end)

        it("normalizes root folder binds for exact and subtree candidate queries", function()
            local prepared = {}
            mock_conn.prepare = function(self, sql)
                local statement = {
                    sql = sql,
                    bind = function(self, ...)
                        self.bound_values = { ... }
                        return self
                    end,
                    step = function()
                        return nil
                    end,
                    reset = function() end,
                    finalize = function() end,
                    clearbind = function(self)
                        return self
                    end,
                }
                prepared[#prepared + 1] = statement
                return statement
            end
            package.loaded["util"].directoryExists = function(path)
                return path == "/"
            end

            BookInfoManager.db_conn = nil
            BookInfoManager.db_created = true
            BookInfoManager:getFolderCoverCandidateFilepaths("/", false)
            BookInfoManager:getFolderCoverCandidateFilepaths("/", true)

            local direct_values
            local subtree_values
            for _, statement in ipairs(prepared) do
                if statement.sql:match("directory%s*=%?") then
                    direct_values = statement.bound_values
                elseif statement.sql:match("directory%s*>=%?") then
                    subtree_values = statement.bound_values
                end
            end
            assert.same({ "/" }, direct_values)
            assert.same({ "/", "0" }, subtree_values)
        end)

        it("returns the final four deterministic folder-cover candidates across the full subtree", function()
            local bound_values
            local rows = {}
            for i = 1, 40 do
                rows[i] = { "/books/library/", string.format("%02d.epub", i) }
            end
            mock_conn.prepare = function(self, sql)
                return {
                    bind = function(self, ...)
                        bound_values = { ... }
                        return self
                    end,
                    step = function(self)
                        return table.remove(rows, 1)
                    end,
                    reset = function() end,
                    finalize = function() end,
                    clearbind = function()
                        return {
                            reset = function() end,
                        }
                    end,
                }
            end
            package.loaded["util"].directoryExists = function(path)
                return path == "/books/library"
            end
            package.loaded["util"].fileExists = function(path)
                return path:match("^/books/library/")
            end
            package.loaded["libs/libkoreader-lfs"].attributes = function(path, attr)
                if attr == "mode" then
                    return "file"
                end
                return nil
            end

            BookInfoManager.db_conn = nil
            BookInfoManager.db_created = true

            local result = BookInfoManager:getFolderCoverCandidateFilepaths("/books/library", true)

            assert.same({ "/books/library/", "/books/library0" }, bound_values)
            assert.same({
                "/books/library/01.epub",
                "/books/library/14.epub",
                "/books/library/27.epub",
                "/books/library/40.epub",
            }, result)
        end)

        it("bounds subtree candidate scanning before filesystem validation", function()
            local step_calls = 0
            local file_exists_calls = 0
            local rows = {}
            for i = 1, 200 do
                rows[i] = { "/books/library/", string.format("%03d.epub", i) }
            end
            mock_conn.prepare = function(self, sql)
                return {
                    bind = function(self, ...)
                        return self
                    end,
                    step = function(self)
                        step_calls = step_calls + 1
                        return table.remove(rows, 1)
                    end,
                    reset = function() end,
                    finalize = function() end,
                    clearbind = function()
                        return {
                            reset = function() end,
                        }
                    end,
                }
            end
            package.loaded["util"].directoryExists = function(path)
                return path == "/books/library"
            end
            package.loaded["util"].fileExists = function(path)
                file_exists_calls = file_exists_calls + 1
                return path:match("^/books/library/")
            end
            package.loaded["libs/libkoreader-lfs"].attributes = function(path, attr)
                if attr == "mode" then
                    return "file"
                end
                return nil
            end

            BookInfoManager.db_conn = nil
            BookInfoManager.db_created = true

            local result = BookInfoManager:getFolderCoverCandidateFilepaths("/books/library", true)

            assert.same({
                "/books/library/001.epub",
                "/books/library/022.epub",
                "/books/library/043.epub",
                "/books/library/064.epub",
            }, result)
            assert.equal(64, file_exists_calls)
            assert.equal(64, step_calls)
        end)

        it("continues past stale rows until it finds valid folder-cover candidates", function()
            local step_calls = 0
            local rows = {}
            for i = 1, 64 do
                rows[i] = { "/books/library/", string.format("stale-%03d.epub", i) }
            end
            rows[65] = { "/books/library/", "valid.epub" }
            mock_conn.prepare = function(self, sql)
                return {
                    bind = function(self, ...)
                        return self
                    end,
                    step = function(self)
                        step_calls = step_calls + 1
                        return table.remove(rows, 1)
                    end,
                    reset = function() end,
                    finalize = function() end,
                    clearbind = function(self)
                        return self
                    end,
                }
            end
            package.loaded["util"].directoryExists = function(path)
                return path == "/books/library"
            end
            package.loaded["util"].fileExists = function(path)
                return path == "/books/library/valid.epub"
            end

            BookInfoManager.db_conn = nil
            BookInfoManager.db_created = true

            local result = BookInfoManager:getFolderCoverCandidateFilepaths("/books/library", true)

            assert.same({ "/books/library/valid.epub" }, result)
            assert.equal(66, step_calls)
        end)

        it("prefers direct-folder covers while filling remaining slots from descendants", function()
            local rows = {
                { "/books/library/", "direct-a.epub" },
                { "/books/library/", "direct-b.epub" },
                { "/books/library/", "direct-c.epub" },
            }
            for index = 1, 8 do
                rows[#rows + 1] = {
                    "/books/library/sub/",
                    string.format("descendant-%02d.epub", index),
                }
            end
            local stmt = {
                bind = function() end,
                step = function()
                    return table.remove(rows, 1)
                end,
                clearbind = function(self) return self end,
                reset = function(self) return self end,
            }
            mock_conn.prepare = function()
                return stmt
            end
            mock_conn.exec = function() return true end
            package.loaded["util"].directoryExists = function() return true end
            package.loaded["util"].fileExists = function() return true end
            BookInfoManager.db_conn = nil
            BookInfoManager.db_created = true

            local result = BookInfoManager:getFolderCoverCandidateFilepaths("/books/library", true)

            assert.same({
                "/books/library/direct-a.epub",
                "/books/library/direct-b.epub",
                "/books/library/direct-c.epub",
                "/books/library/sub/descendant-01.epub",
            }, result)
        end)

    end)

    describe("Cover cache safety", function()
        it("sizes the KOReader cover cache with a realistic average cover footprint", function()
            package.loaded["bookinfomanager"] = nil
            BookInfoManager = require("bookinfomanager")
            BookInfoManager:clearCoverCache()

            local cache = created_cover_caches[#created_cover_caches]

            assert.is_table(cache)
            assert.equal(BookInfoManager.max_cover_dimen * BookInfoManager.max_cover_dimen * 2, cache.avg_itemsize)
            assert.equal(35, cache.slots)
        end)

        it("reduces the cover-cache budget when free memory is constrained", function()
            local util = package.loaded["util"]
            local original_calc_free_mem = util.calcFreeMem
            util.calcFreeMem = function()
                return 32 * 1024 * 1024
            end
            package.loaded["bookinfomanager"] = nil
            BookInfoManager = require("bookinfomanager")
            BookInfoManager:clearCoverCache()

            local cache = created_cover_caches[#created_cover_caches]

            util.calcFreeMem = original_calc_free_mem
            package.loaded["bookinfomanager"] = nil
            BookInfoManager = require("bookinfomanager")
            assert.equal(4 * 1024 * 1024, cache.size)
            assert.is_true(cache.slots < 35)
        end)

        it("stores a clone so later caller mutations do not poison the cache", function()
            local filepath = "/books/cache-safe.epub"
            local original = {
                has_cover = "Y",
                series = "Original Series",
                cover_h = 1,
                cover_bb_stride = 1024,
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

        it("evicts cached covers by byte budget rather than unbounded slot growth", function()
            local mib = 1024 * 1024

            local function make_cached_cover(id)
                return {
                    has_cover = "Y",
                    cover_h = 1,
                    cover_bb_stride = 10 * mib,
                    cover_bb = { id = id },
                }
            end

            BookInfoManager:clearCoverCache()
            BookInfoManager:cacheCover("/books/one.epub", make_cached_cover(1))
            BookInfoManager:cacheCover("/books/two.epub", make_cached_cover(2))
            BookInfoManager:cacheCover("/books/three.epub", make_cached_cover(3))

            assert.is_false(BookInfoManager:isCoverCached("/books/one.epub"))
            assert.is_true(BookInfoManager:isCoverCached("/books/two.epub"))
            assert.is_true(BookInfoManager:isCoverCached("/books/three.epub"))
        end)

        it("removes specific cached covers and clears the full cache through the public API", function()
            local cached = {
                has_cover = "Y",
                cover_h = 1,
                cover_bb_stride = 1024,
                cover_bb = { id = 7 },
            }

            BookInfoManager:clearCoverCache()
            BookInfoManager:cacheCover("/books/remove.epub", cached)
            BookInfoManager:cacheCover("/books/keep.epub", cached)

            BookInfoManager:invalidateCachedCover("/books/remove.epub")
            assert.is_false(BookInfoManager:isCoverCached("/books/remove.epub"))
            assert.is_true(BookInfoManager:isCoverCached("/books/keep.epub"))

            BookInfoManager:clearCoverCache()
            assert.is_false(BookInfoManager:isCoverCached("/books/keep.epub"))
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

    describe("Parent cache invalidation after background extraction", function()
        it("invalidates parent cover and folder caches when a child process finishes", function()
            local filepath = "/books/refreshed.epub"
            local FFIUtil = package.loaded["ffi/util"]
            local UIManager = package.loaded["ui/uimanager"]
            local Device = package.loaded["device"]
            FFIUtil.isSubProcessDone = function(pid)
                return pid == 1234
            end
            UIManager.allowStandby = function() end
            Device.enableCPUCores = function() end

            BookInfoManager:clearCoverCache()
            BookInfoManager:cacheCover(filepath, {
                has_cover = "Y",
                cover_h = 1,
                cover_bb_stride = 1024,
                cover_bb = { id = "stale" },
            })
            folder_cache_invalidations = {}
            BookInfoManager.subprocesses_pids = { 1234 }
            BookInfoManager.subprocess_filepaths = {
                [1234] = { filepath },
            }

            BookInfoManager:collectSubprocesses()

            assert.is_nil(BookInfoManager:getCachedCover(filepath))
            assert.same({ filepath }, folder_cache_invalidations)
            assert.is_nil(BookInfoManager.subprocess_filepaths[1234])
        end)
    end)
end)

require 'busted.runner'()

describe("BookInfoManager", function()
    local BookInfoManager
    local queries = {}
    local mock_conn

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
            fileExists = function() return false end
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

        -- Now require the module
        BookInfoManager = require("bookinfomanager")
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
end)

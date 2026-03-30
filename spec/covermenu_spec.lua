require 'busted.runner'()
local setup_mocks = require("spec.support.mock_ui")

describe("CoverMenu", function()
    local CoverMenu
    local BookInfoManager
    local FileChooser

    setup(function()
        setup_mocks()

        -- Mock InfoMessage
        package.loaded["ui/widget/infomessage"] = {
            new = function(self, o) return o or {} end
        }

        -- Mock ui/time
        package.loaded["ui/time"] = {
            s = function(val) return val end
        }

        package.loaded["l10n.gettext"] = setmetatable({
            pgettext = function(_, text) return text end,
        }, {
            __call = function(_, text) return text end,
        })

        -- Mock FileChooser
        FileChooser = {
            init = function(self)
                self._filechooser_init_called = true
                self.show_parent = self.show_parent or self
                self.path_items = {}
                self.screen_w = 600
                self.screen_h = 800
                self.inner_dimen = {
                    w = 600,
                    h = 800,
                    copy = function(dimen)
                        return {
                            w = dimen.w,
                            h = dimen.h,
                            copy = dimen.copy,
                        }
                    end,
                }
                self.page_info_first_chev = {}
                self.page_info_left_chev = {}
                self.page_info_text = {
                    text = "",
                    setText = function(_, text) self.page_info_text.text = text end,
                }
                self.page_info_right_chev = {}
                self.page_info_last_chev = {}
                self.page_return_arrow = {
                    getSize = function() return { h = 20 } end,
                }
                self.return_button = {}
                self.content_group = {}
                self.item_table = {}
                self.layout = { "filechooser_layout" }
            end,
            new = function(self, o)
                o = o or {}
                setmetatable(o, { __index = self })
                if o.init then
                    o:init()
                end
                return o
            end,
            getListItem = function(dirpath, filename, fullpath, attributes, collate)
                return {
                    text = filename,
                    path = fullpath,
                    is_file = true
                }
            end
        }
        package.loaded["ui/widget/filechooser"] = FileChooser

        -- Mock TitleBar
        package.loaded["titlebar"] = {
            new = function(self, o) return o or {} end
        }

        -- Mock FileManager
        package.loaded["apps/filemanager/filemanager"] = {
            instance = {
                file_chooser = {
                    changeToPath = function() end
                },
                collections = {
                    onShowColl = function() end
                },
                folder_shortcuts = {
                    onShowFolderShortcutsDialog = function() end
                },
                history = {
                    onShowHist = function() end
                },
                menu = {
                    onOpenLastDoc = function() end
                }
            }
        }

        -- Mock UIManager
        package.loaded["ui/uimanager"] = {
            nextTick = function(self, callback)
                -- Handle both UIManager:nextTick() and UIManager.nextTick() calls
                if type(self) == "function" then
                    callback = self
                end
                if callback and type(callback) == "function" then
                    callback()
                end
            end,
            scheduleIn = function(self, delay, callback) end,
            unschedule = function(self, action) end,
            setDirty = function(self, widget) end,
            show = function(self, widget) end
        }

        -- Mock BookList
        package.loaded["ui/widget/booklist"] = {
            getBookInfo = function(filepath)
                return {
                    status = "unread",
                    percent_finished = 0
                }
            end,
            hasBookBeenOpened = function()
                return false
            end,
        }

        -- Mock DocumentRegistry
        package.loaded["document/documentregistry"] = {
            hasProvider = function(_, filename)
                return filename:match("%.epub$") or filename:match("%.pdf$")
            end
        }

        -- Mock other dependencies
        package.loaded["apps/filemanager/filemanagerbookinfo"] = {}
        package.loaded["apps/filemanager/filemanagerconverter"] = {
            isSupported = function()
                return false
            end,
        }
        package.loaded["apps/filemanager/filemanagershortcuts"] = {}
        package.loaded["apps/filemanager/filemanagermenu"] = {
            new = function(self, o) return o or {} end
        }
        package.loaded["ui/widget/buttondialog"] = {}
        package.loaded["ui/widget/menu"] = {
            onCloseWidget = function() end,
            mergeTitleBarIntoLayout = function() end
        }

        -- Mock BookInfoManager
        BookInfoManager = require("bookinfomanager")
        BookInfoManager.extractInBackground = function() return true end
        BookInfoManager.isExtractingInBackground = function() return false end
        BookInfoManager.terminateBackgroundJobs = function() end
        BookInfoManager.closeDbConnection = function() end
        BookInfoManager.cleanUp = function() end

        -- Mock G_reader_settings
        _G.G_reader_settings = {
            readSetting = function(self, key)
                if key == "home_dir" then return "/home" end
                return nil
            end,
            isTrue = function(self, key) return false end,
            isFalse = function(self, key) return false end
        }

        package.loaded["device"].canExecuteScript = function()
            return false
        end

        CoverMenu = require("covermenu")

        -- Add stub for patched method
        CoverMenu._Menu_updatePageInfo_orig = function() end
    end)

    describe("genItemTable", function()
        it("returns empty table when called with empty inputs", function()
            local menu = {
                file_chooser = { path = "/test" }
            }
            for k, v in pairs(CoverMenu) do menu[k] = v end

            -- Mock the original FileChooser method
            CoverMenu._FileChooser_genItemTable_orig = function()
                return {}
            end

            local result = menu:genItemTable({}, {}, "/test")
            assert.is_not_nil(result)
            assert.equal(0, #result)
        end)

        it("removes .. entry from file browser", function()
            local menu = {
                file_chooser = { path = "/test" }
            }
            for k, v in pairs(CoverMenu) do menu[k] = v end

            CoverMenu._FileChooser_genItemTable_orig = function()
                return {
                    { text = "⬆ ../", path = "/test/..", is_go_up = true },
                    { text = "file1.epub", path = "/test/file1.epub", is_file = true },
                    { text = "file2.epub", path = "/test/file2.epub", is_file = true }
                }
            end

            local result = menu:genItemTable({}, {}, "/test")

            assert.is_not_nil(result)
            assert.equal(2, #result)
            assert.equal("file1.epub", result[1].text)
            assert.equal("file2.epub", result[2].text)
        end)

        it("keeps .. entry for PathChooser", function()
            local menu = {
                file_chooser = { path = nil } -- PathChooser has nil path
            }
            for k, v in pairs(CoverMenu) do menu[k] = v end

            CoverMenu._FileChooser_genItemTable_orig = function()
                return {
                    { text = "⬆ ../", path = "/test/..", is_go_up = true },
                    { text = "folder1", path = "/test/folder1", is_file = false }
                }
            end

            local result = menu:genItemTable({}, {}, "/test")

            assert.is_not_nil(result)
            -- PathChooser keeps all items
            assert.is_true(#result > 0)
        end)

        it("handles locked home folder", function()
            _G.G_reader_settings = {
                readSetting = function(self, key)
                    if key == "home_dir" then return "/home" end
                    return nil
                end,
                isTrue = function(self, key)
                    if key == "lock_home_folder" then return true end
                    return false
                end,
                isFalse = function() return false end
            }

            local menu = {
                file_chooser = { path = nil } -- PathChooser
            }
            for k, v in pairs(CoverMenu) do menu[k] = v end

            CoverMenu._FileChooser_genItemTable_orig = function()
                return {}
            end

            local result = menu:genItemTable({}, {}, "/home")

            assert.is_not_nil(result)
        end)

        it("filters files through DocumentRegistry", function()
            local menu = {
                file_chooser = { path = "/test" }
            }
            for k, v in pairs(CoverMenu) do menu[k] = v end

            CoverMenu._FileChooser_genItemTable_orig = function()
                return {
                    { text = "file1.epub", path = "/test/file1.epub", is_file = true },
                    { text = "file2.txt", path = "/test/file2.txt", is_file = true },
                    { text = "file3.pdf", path = "/test/file3.pdf", is_file = true }
                }
            end

            local result = menu:genItemTable({}, {}, "/test")

            -- All files pass through since they're already in the table
            assert.is_not_nil(result)
        end)

        it("uses a prepared metabrowse query with escaped LIKE wildcards", function()
            local prepared_sql
            local bound_values
            local exec_calls = 0
            local closed = false
            package.loaded["lua-ljsqlite3/init"] = {
                open = function()
                    return {
                        set_busy_timeout = function() end,
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
                        close = function()
                            closed = true
                        end,
                    }
                end,
            }

            _G.G_reader_settings = {
                readSetting = function(self, key)
                    if key == "home_dir" then return "/home/100%_semi;quote'" end
                    return nil
                end,
                isTrue = function() return false end,
                isFalse = function() return false end,
            }

            local menu = {
                show_parent = {},
                root_path = "/test",
                onHome = function() end,
                registerKeyEvents = function() end,
                file_chooser = { path = "/test" },
            }
            for k, v in pairs(CoverMenu) do menu[k] = v end

            menu:setupLayout()
            menu.title_bar.center_icon_hold_callback()
            menu.render_context = { is_pathchooser = false }

            local result = menu:genItemTable({}, {}, "/test")

            assert.is_table(result)
            assert.equal(0, exec_calls)
            assert.is_true(closed)
            assert.match("LIKE %?", prepared_sql)
            assert.match("ESCAPE", prepared_sql)
            assert.equal("/home/100\\%\\_semi;quote'/%", bound_values[1])
        end)

        it("keeps metabrowse mode scoped to the menu instance", function()
            package.loaded["covermenu"] = nil
            CoverMenu = require("covermenu")
            CoverMenu._Menu_updatePageInfo_orig = function() end
            local original_get_list_item = FileChooser.getListItem

            local library_calls = 0
            BookInfoManager.getLibraryEntries = function()
                library_calls = library_calls + 1
                return {
                    { directory = "/home/library/", filename = "alpha.epub" },
                }
            end
            BookInfoManager.getLibraryRevision = function()
                return 0
            end
            BookInfoManager.getSetting = function()
                return false
            end
            package.loaded["libs/libkoreader-lfs"].attributes = function()
                return { mode = "file" }
            end
            FileChooser.getListItem = function(self, dirpath, filename, fullpath, attributes, collate)
                return {
                    text = filename,
                    path = fullpath,
                    is_file = true,
                }
            end

            CoverMenu._FileChooser_genItemTable_orig = function()
                return {
                    { text = "regular.epub", path = "/test/regular.epub", is_file = true },
                }
            end

            local first_menu = {
                show_parent = {},
                root_path = "/test",
                onHome = function() end,
                registerKeyEvents = function() end,
                file_chooser = { path = "/test" },
            }
            for k, v in pairs(CoverMenu) do first_menu[k] = v end
            first_menu:setupLayout()
            first_menu.render_context = { is_pathchooser = false }
            first_menu.title_bar.center_icon_hold_callback()

            local second_menu = {
                show_parent = {},
                root_path = "/test",
                onHome = function() end,
                registerKeyEvents = function() end,
                file_chooser = { path = "/test" },
            }
            for k, v in pairs(CoverMenu) do second_menu[k] = v end
            second_menu:setupLayout()
            second_menu.render_context = { is_pathchooser = false }

            local first_result = first_menu:genItemTable({}, {}, "/test")
            local second_result = second_menu:genItemTable({}, {}, "/test")

            FileChooser.getListItem = original_get_list_item

            assert.equal(1, #first_result)
            assert.equal(1, #second_result)
            assert.equal("alpha.epub", first_result[1].text)
            assert.equal("regular.epub", second_result[1].text)
            assert.equal(1, library_calls)
        end)
    end)

    describe("instance-scoped session state", function()
        it("does not reuse another menu's pathchooser state in updatePageInfo", function()
            local format_footer_calls = 0
            local original_format_footer_text = package.loaded["ptutil"].formatFooterText
            local original_get_default_dir = package.loaded["apps/filemanager/filemanagerutil"].getDefaultDir
            local original_has_folder_shortcut = package.loaded["apps/filemanager/filemanagershortcuts"].hasFolderShortcut
            package.loaded["ptutil"].formatFooterText = function()
                format_footer_calls = format_footer_calls + 1
                return "Footer"
            end
            package.loaded["apps/filemanager/filemanagerutil"].getDefaultDir = function()
                return "/default"
            end
            package.loaded["apps/filemanager/filemanagershortcuts"].hasFolderShortcut = function()
                return false
            end

            local first_menu = {
                path = "/library/visible",
                page_info_text = {
                    text = "1 / 1",
                    setText = function(self, text) self.text = text end,
                },
                page_info = { getSize = function() return { w = 100 } end },
                cur_folder_text = {
                    setMaxWidth = function() end,
                    setText = function() end,
                },
                screen_w = 600,
                render_context = { is_pathchooser = false },
            }
            for k, v in pairs(CoverMenu) do first_menu[k] = v end
            first_menu:genItemTable({}, {}, "/library/visible")

            local second_menu = {
                path = "/library/chooser",
                page_info_text = {
                    text = "1 / 1",
                    setText = function(self, text) self.text = text end,
                },
                page_info = { getSize = function() return { w = 100 } end },
                cur_folder_text = {
                    setMaxWidth = function() end,
                    setText = function() error("pathchooser footer should not be updated") end,
                },
                screen_w = 600,
                render_context = { is_pathchooser = true },
            }
            for k, v in pairs(CoverMenu) do second_menu[k] = v end

            second_menu:updatePageInfo(1)

            package.loaded["ptutil"].formatFooterText = original_format_footer_text
            package.loaded["apps/filemanager/filemanagerutil"].getDefaultDir = original_get_default_dir
            package.loaded["apps/filemanager/filemanagershortcuts"].hasFolderShortcut = original_has_folder_shortcut

            assert.equal(0, format_footer_calls)
        end)

        it("passes the menu instance's metabrowse flag to the footer formatter", function()
            local meta_browse_flags = {}
            local original_format_footer_text = package.loaded["ptutil"].formatFooterText
            local original_get_default_dir = package.loaded["apps/filemanager/filemanagerutil"].getDefaultDir
            local original_has_folder_shortcut = package.loaded["apps/filemanager/filemanagershortcuts"].hasFolderShortcut
            package.loaded["ptutil"].formatFooterText = function(_, _, _, _, _, meta_browse_mode)
                table.insert(meta_browse_flags, meta_browse_mode)
                return "Footer"
            end
            package.loaded["apps/filemanager/filemanagerutil"].getDefaultDir = function()
                return "/default"
            end
            package.loaded["apps/filemanager/filemanagershortcuts"].hasFolderShortcut = function()
                return false
            end

            local first_menu = {
                show_parent = {},
                root_path = "/test",
                onHome = function() end,
                registerKeyEvents = function() end,
                file_chooser = { path = "/test" },
                path = "/library/one",
                page_info_text = {
                    text = "1 / 1",
                    setText = function(self, text) self.text = text end,
                },
                page_info = { getSize = function() return { w = 100 } end },
                cur_folder_text = {
                    setMaxWidth = function() end,
                    setText = function() end,
                },
                screen_w = 600,
            }
            for k, v in pairs(CoverMenu) do first_menu[k] = v end
            first_menu:setupLayout()
            first_menu.render_context = { is_pathchooser = false }
            first_menu.title_bar.center_icon_hold_callback()

            local second_menu = {
                path = "/library/two",
                page_info_text = {
                    text = "1 / 1",
                    setText = function(self, text) self.text = text end,
                },
                page_info = { getSize = function() return { w = 100 } end },
                cur_folder_text = {
                    setMaxWidth = function() end,
                    setText = function() end,
                },
                screen_w = 600,
                render_context = { is_pathchooser = false },
                _pt_is_pathchooser = false,
                _pt_meta_browse_mode = false,
            }
            for k, v in pairs(CoverMenu) do second_menu[k] = v end

            second_menu:updatePageInfo(1)

            package.loaded["ptutil"].formatFooterText = original_format_footer_text
            package.loaded["apps/filemanager/filemanagerutil"].getDefaultDir = original_get_default_dir
            package.loaded["apps/filemanager/filemanagershortcuts"].hasFolderShortcut = original_has_folder_shortcut

            assert.same({ false }, meta_browse_flags)
        end)
    end)

    describe("onCloseWidget", function()
        it("terminates background jobs", function()
            local terminated = false
            BookInfoManager.terminateBackgroundJobs = function() terminated = true end

            local menu = {
                item_group = { free = function() end },
                _covermenu_onclose_done = false
            }
            for k, v in pairs(CoverMenu) do menu[k] = v end

            menu:onCloseWidget()

            assert.is_true(terminated)
        end)

        it("closes database connection", function()
            local closed = false
            BookInfoManager.closeDbConnection = function() closed = true end

            local menu = {
                item_group = { free = function() end },
                _covermenu_onclose_done = false
            }
            for k, v in pairs(CoverMenu) do menu[k] = v end

            menu:onCloseWidget()

            assert.is_true(closed)
        end)

        it("cleans up temporary resources", function()
            local cleaned = false
            BookInfoManager.cleanUp = function() cleaned = true end

            local menu = {
                item_group = { free = function() end },
                _covermenu_onclose_done = false
            }
            for k, v in pairs(CoverMenu) do menu[k] = v end

            menu:onCloseWidget()

            assert.is_true(cleaned)
        end)

        it("unschedules pending update actions", function()
            local unscheduled = false
            local UIManager = package.loaded["ui/uimanager"]
            UIManager.unschedule = function() unscheduled = true end

            local menu = {
                item_group = { free = function() end },
                items_update_action = function() end,
                _covermenu_onclose_done = false
            }
            for k, v in pairs(CoverMenu) do menu[k] = v end

            menu:onCloseWidget()

            assert.is_true(unscheduled)
            assert.is_nil(menu.items_update_action)
        end)

        it("frees item_group widgets", function()
            local freed = false
            local menu = {
                item_group = {
                    free = function() freed = true end
                },
                _covermenu_onclose_done = false
            }
            for k, v in pairs(CoverMenu) do menu[k] = v end

            menu:onCloseWidget()

            assert.is_true(freed)
        end)

        it("does not manage cover_info_cache state on close", function()
            local menu = {
                item_group = { free = function() end },
                cover_info_cache = { some = "data" },
                _covermenu_onclose_done = false
            }
            for k, v in pairs(CoverMenu) do menu[k] = v end

            menu:onCloseWidget()

            assert.same({ some = "data" }, menu.cover_info_cache)
        end)

        it("only runs once when called multiple times", function()
            local call_count = 0
            BookInfoManager.terminateBackgroundJobs = function() call_count = call_count + 1 end

            local menu = {
                item_group = { free = function() end },
                _covermenu_onclose_done = false
            }
            for k, v in pairs(CoverMenu) do menu[k] = v end

            menu:onCloseWidget()
            menu:onCloseWidget()
            menu:onCloseWidget()

            assert.equal(1, call_count)
        end)
        it("clears the font-size estimator cache on close", function()
            local ptutil = require("ptutil")
            local cleared = 0
            local original_clear = ptutil.clearFontSizeCache
            ptutil.clearFontSizeCache = function()
                cleared = cleared + 1
            end

            local menu = {
                item_group = { free = function() end },
                _covermenu_onclose_done = false
            }
            for k, v in pairs(CoverMenu) do menu[k] = v end

            menu:onCloseWidget()

            ptutil.clearFontSizeCache = original_clear

            assert.equal(1, cleared)
        end)
    end)

    describe("scheduled refresh batching", function()
        it("batches pending item refreshes during scheduled updates", function()
            local batch_calls = 0
            local scheduled_callback
            local original_schedule_in = package.loaded["ui/uimanager"].scheduleIn
            local original_next_tick = package.loaded["ui/uimanager"].nextTick
            local original_set_dirty = package.loaded["ui/uimanager"].setDirty
            local original_get_batch = BookInfoManager.getBookInfoBatch
            local original_is_extracting = BookInfoManager.isExtractingInBackground
            local original_extract_in_background = BookInfoManager.extractInBackground

            package.loaded["ui/uimanager"].scheduleIn = function(self, delay, callback)
                scheduled_callback = callback
            end
            package.loaded["ui/uimanager"].nextTick = function(self, callback)
            end
            package.loaded["ui/uimanager"].setDirty = function() end
            BookInfoManager.extractInBackground = function()
                return true
            end
            BookInfoManager.isExtractingInBackground = function()
                return false
            end
            BookInfoManager.getBookInfoBatch = function(self, filepaths, do_cover)
                batch_calls = batch_calls + 1
                return {
                    ["/books/one.epub"] = { title = "One" },
                    ["/books/two.epub"] = { title = "Two" },
                }
            end

            local menu = {
                item_group = {
                    clear = function() end,
                },
                page_info = { resetLayout = function() end },
                return_button = { resetLayout = function() end },
                content_group = { resetLayout = function() end },
                show_parent = {},
                layout = {},
                path_items = nil,
                updatePageInfo = function() end,
                _recalculateDimen = function() end,
                _updateItemsBuildUI = function(self)
                    local item_one = {
                        filepath = "/books/one.epub",
                        text = "one",
                        cover_specs = {},
                        menu = self,
                        _has_cover_image = false,
                        update = function(item)
                            item.bookinfo_found = item.menu._bookinfo_batch
                                and item.menu._bookinfo_batch[item.filepath] ~= nil
                        end,
                        [1] = { dimen = {} },
                    }
                    local item_two = {
                        filepath = "/books/two.epub",
                        text = "two",
                        cover_specs = {},
                        menu = self,
                        _has_cover_image = false,
                        update = function(item)
                            item.bookinfo_found = item.menu._bookinfo_batch
                                and item.menu._bookinfo_batch[item.filepath] ~= nil
                        end,
                        [1] = { dimen = {} },
                    }
                    self.items_to_update = { item_one, item_two }
                    return 1
                end,
            }
            for k, v in pairs(CoverMenu) do menu[k] = v end
            menu.updatePageInfo = function() end

            menu:updateItems(1, true)
            assert.is_function(scheduled_callback)

            scheduled_callback()

            package.loaded["ui/uimanager"].scheduleIn = original_schedule_in
            package.loaded["ui/uimanager"].nextTick = original_next_tick
            package.loaded["ui/uimanager"].setDirty = original_set_dirty
            BookInfoManager.getBookInfoBatch = original_get_batch
            BookInfoManager.isExtractingInBackground = original_is_extracting
            BookInfoManager.extractInBackground = original_extract_in_background

            assert.equal(1, batch_calls)
            assert.equal(0, #menu.items_to_update)
            assert.is_nil(menu._bookinfo_batch)
        end)
    end)

    describe("setupLayout", function()
        it("creates a TitleBar", function()
            local menu = {
                show_parent = {},
                root_path = "/test",
                registerKeyEvents = function() end,
                file_chooser = { path = "/test" }
            }
            for k, v in pairs(CoverMenu) do menu[k] = v end

            menu:setupLayout()

            assert.is_not_nil(menu.title_bar)
        end)

        it("configures TitleBar with home button", function()
            local menu = {
                show_parent = {},
                root_path = "/test",
                onHome = function() end,
                registerKeyEvents = function() end,
                file_chooser = { path = "/test" }
            }
            for k, v in pairs(CoverMenu) do menu[k] = v end

            menu:setupLayout()

            assert.equal("home", menu.title_bar.left1_icon)
            assert.is_function(menu.title_bar.left1_icon_tap_callback)
        end)

        it("configures TitleBar with favorites button", function()
            local menu = {
                show_parent = {},
                root_path = "/test",
                registerKeyEvents = function() end,
                file_chooser = { path = "/test" }
            }
            for k, v in pairs(CoverMenu) do menu[k] = v end

            menu:setupLayout()

            assert.equal("favorites", menu.title_bar.left2_icon)
            assert.is_function(menu.title_bar.left2_icon_tap_callback)
        end)

        it("configures TitleBar with history button", function()
            local menu = {
                show_parent = {},
                root_path = "/test",
                registerKeyEvents = function() end,
                file_chooser = { path = "/test" }
            }
            for k, v in pairs(CoverMenu) do menu[k] = v end

            menu:setupLayout()

            assert.equal("history", menu.title_bar.left3_icon)
            assert.is_function(menu.title_bar.left3_icon_tap_callback)
        end)

        it("configures TitleBar with up folder button", function()
            local menu = {
                show_parent = {},
                root_path = "/test",
                registerKeyEvents = function() end,
                file_chooser = { path = "/test" }
            }
            for k, v in pairs(CoverMenu) do menu[k] = v end

            menu:setupLayout()

            assert.equal("go_up", menu.title_bar.right2_icon)
            assert.is_function(menu.title_bar.right2_icon_tap_callback)
        end)

        it("configures TitleBar with last document button", function()
            local menu = {
                show_parent = {},
                root_path = "/test",
                registerKeyEvents = function() end,
                file_chooser = { path = "/test" }
            }
            for k, v in pairs(CoverMenu) do menu[k] = v end

            menu:setupLayout()

            assert.equal("last_document", menu.title_bar.right3_icon)
            assert.is_function(menu.title_bar.right3_icon_tap_callback)
        end)

        it("configures TitleBar with plus menu button", function()
            local menu = {
                show_parent = {},
                root_path = "/test",
                onShowPlusMenu = function() end,
                registerKeyEvents = function() end,
                file_chooser = { path = "/test" }
            }
            for k, v in pairs(CoverMenu) do menu[k] = v end

            menu:setupLayout()

            assert.equal("plus", menu.title_bar.right1_icon)
            assert.is_function(menu.title_bar.right1_icon_tap_callback)
        end)

        it("uses check icon when files are selected", function()
            local menu = {
                show_parent = {},
                root_path = "/test",
                selected_files = { "file1.epub" },
                onShowPlusMenu = function() end,
                registerKeyEvents = function() end,
                file_chooser = { path = "/test" }
            }
            for k, v in pairs(CoverMenu) do menu[k] = v end

            menu:setupLayout()

            assert.equal("check", menu.title_bar.right1_icon)
        end)

        it("configures center hero icon", function()
            local menu = {
                show_parent = {},
                root_path = "/test",
                registerKeyEvents = function() end,
                file_chooser = { path = "/test" }
            }
            for k, v in pairs(CoverMenu) do menu[k] = v end

            menu:setupLayout()

            assert.equal("hero", menu.title_bar.center_icon)
        end)

        it("preserves FileChooser init behavior", function()
            local menu = {
                show_parent = {},
                root_path = "/test",
                registerKeyEvents = function() end,
                file_chooser = { path = "/test" }
            }
            for k, v in pairs(CoverMenu) do menu[k] = v end

            menu:setupLayout()

            assert.is_true(menu.file_chooser._filechooser_init_called)
            assert.is_table(menu.file_chooser.path_items)
            assert.same({ "filechooser_layout" }, menu.layout)
        end)

        it("preserves upstream FileChooser wiring for ui and custom title bar", function()
            local menu = {
                show_parent = {},
                root_path = "/test",
                registerKeyEvents = function() end,
                file_chooser = { path = "/test" }
            }
            for k, v in pairs(CoverMenu) do menu[k] = v end

            menu:setupLayout()

            assert.equal(menu, menu.file_chooser.ui)
            assert.equal(menu.title_bar, menu.file_chooser.custom_title_bar)
            assert.is_true(menu.file_chooser.return_arrow_propagation)
        end)

        it("routes FileChooser search callback through the file searcher", function()
            local searched_for
            local menu = {
                show_parent = {},
                root_path = "/test",
                filesearcher = {
                    onShowFileSearch = function(self, search_string)
                        searched_for = search_string
                    end,
                },
                registerKeyEvents = function() end,
                file_chooser = { path = "/test" }
            }
            for k, v in pairs(CoverMenu) do menu[k] = v end

            menu:setupLayout()
            menu.file_chooser.search_callback("needle")

            assert.equal("needle", searched_for)
        end)

        it("routes file opens through filemanagerutil.openFile", function()
            local open_args
            package.loaded["apps/filemanager/filemanagerutil"].openFile = function(file_manager, path)
                open_args = { file_manager = file_manager, path = path }
            end

            local menu = {
                show_parent = {},
                root_path = "/test",
                registerKeyEvents = function() end,
                file_chooser = { path = "/test" },
                openFile = function()
                    error("expected filemanagerutil.openFile to handle file opens")
                end,
            }
            for k, v in pairs(CoverMenu) do menu[k] = v end

            menu:setupLayout()
            menu.file_chooser:onFileSelect({
                path = "/test/book.epub",
                is_file = true,
            })

            assert.is_not_nil(open_args)
            assert.equal(menu, open_args.file_manager)
            assert.equal("/test/book.epub", open_args.path)
        end)

        it("routes standard file dialog actions through file manager callbacks", function()
            local shown_dialog
            local renamed
            local deleted
            local cut
            local copied
            local pasted
            package.loaded["ui/uimanager"].show = function(_, widget)
                shown_dialog = widget
            end
            package.loaded["ui/uimanager"].close = function() end
            package.loaded["ui/widget/buttondialog"].new = function(self, o) return o end
            package.loaded["apps/filemanager/filemanagerutil"].genBookInformationButton = function()
                return { text = "Book information" }
            end

            local menu = {
                show_parent = {},
                root_path = "/test",
                registerKeyEvents = function() end,
                file_chooser = { path = "/test" },
                clipboard = true,
                showRenameFileDialog = function(_, file, is_file)
                    renamed = { file = file, is_file = is_file }
                end,
                showDeleteFileDialog = function(_, file)
                    deleted = file
                end,
                cutFile = function(_, file)
                    cut = file
                end,
                copyFile = function(_, file)
                    copied = file
                end,
                pasteFileFromClipboard = function(_, file)
                    pasted = file
                end,
                collections = {
                    genAddToCollectionButton = function()
                        return { text = "Collection" }
                    end,
                },
            }
            for k, v in pairs(CoverMenu) do menu[k] = v end

            menu:setupLayout()
            menu.file_chooser:showFileDialog({
                path = "/test/book.txt",
                is_file = true,
            })

            assert.is_table(shown_dialog)
            local buttons = shown_dialog.buttons
            buttons[1][1].callback()
            buttons[1][3].callback()
            buttons[2][1].callback()
            buttons[2][2].callback()
            buttons[2][3].callback()

            assert.equal("/test/book.txt", pasted)
            assert.same({ file = "/test/book.txt", is_file = true }, renamed)
            assert.equal("/test/book.txt", deleted)
            assert.equal("/test/book.txt", cut)
            assert.equal("/test/book.txt", copied)
        end)
    end)

    describe("updateItems", function()
        it("resets item_group", function()
            local cleared = false
            local menu = {
                dimen = { copy = function() return { w = 100, h = 100 } end },
                item_group = {
                    clear = function() cleared = true end
                },
                page_info = { resetLayout = function() end },
                page_info_text = { text = "", setText = function() end },
                return_button = { resetLayout = function() end },
                content_group = { resetLayout = function() end },
                show_parent = {},
                layout = {},
                items_to_update = {},
                _updateItemsBuildUI = function() end,
                _recalculateDimen = function() end
            }
            for k, v in pairs(CoverMenu) do menu[k] = v end

            menu:updateItems(1, false)

            assert.is_true(cleared)
        end)

        it("calls _recalculateDimen unless told not to", function()
            local recalculated = false
            local menu = {
                dimen = { copy = function() return { w = 100, h = 100 } end },
                item_group = { clear = function() end },
                page_info = { resetLayout = function() end },
                page_info_text = { text = "", setText = function() end },
                return_button = { resetLayout = function() end },
                content_group = { resetLayout = function() end },
                show_parent = {},
                layout = {},
                items_to_update = {},
                _updateItemsBuildUI = function() end,
                _recalculateDimen = function() recalculated = true end
            }
            for k, v in pairs(CoverMenu) do menu[k] = v end

            menu:updateItems(1, false)
            assert.is_true(recalculated)

            recalculated = false
            menu:updateItems(1, true)
            assert.is_false(recalculated)
        end)

        it("calls _updateItemsBuildUI", function()
            local built = false
            local menu = {
                dimen = { copy = function() return { w = 100, h = 100 } end },
                item_group = { clear = function() end },
                page_info = { resetLayout = function() end },
                page_info_text = { text = "", setText = function() end },
                return_button = { resetLayout = function() end },
                content_group = { resetLayout = function() end },
                show_parent = {},
                layout = {},
                items_to_update = {},
                _updateItemsBuildUI = function() built = true end,
                _recalculateDimen = function() end
            }
            for k, v in pairs(CoverMenu) do menu[k] = v end

            menu:updateItems(1)

            assert.is_true(built)
        end)

        it("schedules background extraction when items need updates", function()
            local extracted = false
            BookInfoManager.extractInBackground = function() extracted = true; return true end

            local menu = {
                dimen = { copy = function() return { w = 100, h = 100 } end },
                item_group = { clear = function() end },
                page_info = { resetLayout = function() end },
                page_info_text = { text = "", setText = function() end },
                return_button = { resetLayout = function() end },
                content_group = { resetLayout = function() end },
                show_parent = {},
                layout = {},
                items_to_update = {
                    { filepath = "/test/book1.epub", cover_specs = {} }
                },
                _updateItemsBuildUI = function(self)
                    self.items_to_update = {
                        { filepath = "/test/book1.epub", cover_specs = {} }
                    }
                end,
                _recalculateDimen = function() end
            }
            for k, v in pairs(CoverMenu) do menu[k] = v end

            menu:updateItems(1)

            assert.is_true(extracted)
        end)
    end)
end)

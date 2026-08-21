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
        package.loaded["apps/filemanager/filemanagershortcuts"] = {
            hasFolderShortcut = function() return false end,
        }
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

        it("preserves FileChooser's parent-folder row", function()
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
            assert.equal(3, #result)
            assert.is_true(result[1].is_go_up)
            assert.equal("file1.epub", result[2].text)
            assert.equal("file2.epub", result[3].text)
        end)

        it("does not reorder FileChooser's parent-folder row", function()
            local menu = {
                file_chooser = { path = "/test" }
            }
            for k, v in pairs(CoverMenu) do menu[k] = v end

            CoverMenu._FileChooser_genItemTable_orig = function()
                return {
                    { text = "Current folder helper", path = "/test/.", bold = true },
                    { text = "⬆ ../", path = "/test/..", is_go_up = true },
                    { text = "file1.epub", path = "/test/file1.epub", is_file = true },
                }
            end

            local result = menu:genItemTable({}, {}, "/test")

            assert.is_not_nil(result)
            assert.equal(3, #result)
            assert.equal("Current folder helper", result[1].text)
            assert.is_true(result[2].is_go_up)
            assert.equal("file1.epub", result[3].text)
            assert.is_nil(result[1].is_go_up)
            assert.is_nil(result[3].is_go_up)
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

    end)

    describe("setupLayout", function()
        it("configures the file chooser before init builds the first page", function()
            local original_init = FileChooser.init
            local init_state = {}

            FileChooser.init = function(this)
                init_state.display_mode_type = this.display_mode_type
                init_state.updateItems = this.updateItems
                init_state.genItemTable = this.genItemTable
                return original_init(this)
            end

            package.loaded["covermenu"] = nil
            CoverMenu = require("covermenu")
            CoverMenu._Menu_updatePageInfo_orig = function() end
            CoverMenu._FileChooser_genItemTable_orig = function()
                return {}
            end

            local menu = {
                show_parent = {},
                root_path = "/test",
                onHome = function() end,
                registerKeyEvents = function() end,
                _pt_filechooser_display_mode = "list_image_meta",
            }
            for k, v in pairs(CoverMenu) do menu[k] = v end

            menu:setupLayout()

            FileChooser.init = original_init

            assert.equal("list", init_state.display_mode_type)
            assert.equal(CoverMenu.updateItems, init_state.updateItems)
            assert.equal(CoverMenu.genItemTable, init_state.genItemTable)
        end)

        it("restores the saved filemanager display mode when the instance-scoped mode field is missing", function()
            package.loaded["covermenu"] = nil
            CoverMenu = require("covermenu")
            CoverMenu._Menu_updatePageInfo_orig = function() end
            CoverMenu._FileChooser_genItemTable_orig = function()
                return {}
            end

            local original_get_setting = BookInfoManager.getSetting
            BookInfoManager.getSetting = function(_, key)
                if key == "filemanager_display_mode" then
                    return "list_image_meta"
                end
                return original_get_setting(BookInfoManager, key)
            end

            local menu = {
                show_parent = {},
                root_path = "/test",
                onHome = function() end,
                registerKeyEvents = function() end,
            }
            for k, v in pairs(CoverMenu) do menu[k] = v end

            menu:setupLayout()

            BookInfoManager.getSetting = original_get_setting

            assert.equal("list", menu.file_chooser.display_mode_type)
            assert.equal(CoverMenu.updateItems, menu.file_chooser.updateItems)
            assert.equal("list_image_meta", menu._pt_filechooser_display_mode)
        end)

        it("uses left-aligned page controls when configured", function()
            local original_get_setting = BookInfoManager.getSetting
            BookInfoManager.getSetting = function(_, key)
                if key == "footer_page_controls_alignment" then
                    return "left"
                end
                return original_get_setting(BookInfoManager, key)
            end

            local menu = {
                show_parent = {},
                root_path = "/test",
                onHome = function() end,
                registerKeyEvents = function() end,
                _pt_filechooser_display_mode = "list_image_meta",
            }
            for k, v in pairs(CoverMenu) do menu[k] = v end

            menu:setupLayout()

            BookInfoManager.getSetting = original_get_setting

            assert.equal("LeftContainer", menu.file_chooser._pt_page_info_container.name)
        end)

        it("uses centered page controls when configured", function()
            local original_get_setting = BookInfoManager.getSetting
            BookInfoManager.getSetting = function(_, key)
                if key == "footer_page_controls_alignment" then
                    return "center"
                end
                return original_get_setting(BookInfoManager, key)
            end

            local menu = {
                show_parent = {},
                root_path = "/test",
                onHome = function() end,
                registerKeyEvents = function() end,
                _pt_filechooser_display_mode = "list_image_meta",
            }
            for k, v in pairs(CoverMenu) do menu[k] = v end

            menu:setupLayout()

            BookInfoManager.getSetting = original_get_setting

            assert.equal("CenterContainer", menu.file_chooser._pt_page_info_container.name)
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

    end)

    describe("display-menu teardown", function()
        it("unschedules a live footer action before removing display hooks", function()
            local unscheduled_action
            local UIManager = package.loaded["ui/uimanager"]
            local original_unschedule = UIManager.unschedule
            UIManager.unschedule = function(_, action)
                unscheduled_action = action
            end
            local menu = {
                footer_refresh_action = "footer-refresh",
                updateItems = CoverMenu.updateItems,
            }

            CoverMenu.configureDisplayMenu(menu, nil)

            UIManager.unschedule = original_unschedule
            assert.equal("footer-refresh", unscheduled_action)
            assert.is_nil(menu.footer_refresh_action)
        end)

        it("preserves an explicit false opened-hint setting", function()
            local menu = {}

            CoverMenu.configureDisplayMenu(menu, "list_image_meta", {
                do_hint_opened = false,
            })

            assert.is_false(menu._do_hint_opened)
        end)
    end)

    describe("onCloseWidget", function()
        it("terminates background jobs for the owning file browser", function()
            local terminated = false
            BookInfoManager.terminateBackgroundJobs = function() terminated = true end

            local menu = {
                item_group = { free = function() end },
                _pt_owns_bookinfo_session = true,
                _covermenu_onclose_done = false
            }
            for k, v in pairs(CoverMenu) do menu[k] = v end

            menu:onCloseWidget()

            assert.is_true(terminated)
        end)

        it("closes database connection for the owning file browser", function()
            local closed = false
            BookInfoManager.closeDbConnection = function() closed = true end

            local menu = {
                item_group = { free = function() end },
                _pt_owns_bookinfo_session = true,
                _covermenu_onclose_done = false
            }
            for k, v in pairs(CoverMenu) do menu[k] = v end

            menu:onCloseWidget()

            assert.is_true(closed)
        end)

        it("cleans up temporary resources for the owning file browser", function()
            local cleaned = false
            BookInfoManager.cleanUp = function() cleaned = true end

            local menu = {
                item_group = { free = function() end },
                _pt_owns_bookinfo_session = true,
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

        it("unschedules pending footer refresh actions", function()
            local unscheduled = false
            local UIManager = package.loaded["ui/uimanager"]
            UIManager.unschedule = function(_, action)
                if action == "footer-refresh" then
                    unscheduled = true
                end
            end

            local menu = {
                item_group = { free = function() end },
                footer_refresh_action = "footer-refresh",
                _covermenu_onclose_done = false
            }
            for k, v in pairs(CoverMenu) do menu[k] = v end

            menu:onCloseWidget()

            assert.is_true(unscheduled)
            assert.is_nil(menu.footer_refresh_action)
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
                _pt_owns_bookinfo_session = true,
                _covermenu_onclose_done = false
            }
            for k, v in pairs(CoverMenu) do menu[k] = v end

            menu:onCloseWidget()
            menu:onCloseWidget()
            menu:onCloseWidget()

            assert.equal(1, call_count)
        end)
        it("clears the font-size estimator cache when the owning file browser closes", function()
            local ptutil = require("ptutil")
            local cleared = 0
            local original_clear = ptutil.clearFontSizeCache
            ptutil.clearFontSizeCache = function()
                cleared = cleared + 1
            end

            local menu = {
                item_group = { free = function() end },
                _pt_owns_bookinfo_session = true,
                _covermenu_onclose_done = false
            }
            for k, v in pairs(CoverMenu) do menu[k] = v end

            menu:onCloseWidget()

            ptutil.clearFontSizeCache = original_clear

            assert.equal(1, cleared)
        end)

        it("keeps shared jobs, database, and caches alive when a transient menu closes", function()
            local terminate_calls = 0
            local close_calls = 0
            local cleanup_calls = 0
            local folder_cache_clears = 0
            local ptutil = require("ptutil")
            local original_terminate = BookInfoManager.terminateBackgroundJobs
            local original_close = BookInfoManager.closeDbConnection
            local original_cleanup = BookInfoManager.cleanUp
            local original_clear_folder = ptutil.clearFolderCoverCache
            BookInfoManager.terminateBackgroundJobs = function() terminate_calls = terminate_calls + 1 end
            BookInfoManager.closeDbConnection = function() close_calls = close_calls + 1 end
            BookInfoManager.cleanUp = function() cleanup_calls = cleanup_calls + 1 end
            ptutil.clearFolderCoverCache = function() folder_cache_clears = folder_cache_clears + 1 end

            local menu = {
                item_group = { free = function() end },
                _pt_owns_bookinfo_session = false,
                _covermenu_onclose_done = false,
            }
            for k, v in pairs(CoverMenu) do menu[k] = v end

            menu:onCloseWidget()

            BookInfoManager.terminateBackgroundJobs = original_terminate
            BookInfoManager.closeDbConnection = original_close
            BookInfoManager.cleanUp = original_cleanup
            ptutil.clearFolderCoverCache = original_clear_folder
            assert.equal(0, terminate_calls)
            assert.equal(0, close_calls)
            assert.equal(0, cleanup_calls)
            assert.equal(0, folder_cache_clears)
        end)

        it("calls the widget-specific original close handler when present", function()
            local original_close_calls = 0
            local menu = {
                item_group = { free = function() end },
                _covermenu_onclose_done = false,
                _pt_onCloseWidget_orig = function()
                    original_close_calls = original_close_calls + 1
                end,
            }
            for k, v in pairs(CoverMenu) do menu[k] = v end

            menu:onCloseWidget()

            assert.equal(1, original_close_calls)
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

    describe("footer refresh scheduling", function()
        it("schedules live footer refresh when device info footer is enabled", function()
            local scheduled_delay
            local scheduled_callback
            local UIManager = package.loaded["ui/uimanager"]
            local original_schedule_in = UIManager.scheduleIn
            local original_get_setting = BookInfoManager.getSetting

            UIManager.scheduleIn = function(_, delay, callback)
                scheduled_delay = delay
                scheduled_callback = callback
            end
            BookInfoManager.getSetting = function(_, key)
                if key == "replace_footer_text" then
                    return true
                end
                return original_get_setting(BookInfoManager, key)
            end

            local menu = {
                show_parent = {},
                root_path = "/test",
                onHome = function() end,
                registerKeyEvents = function() end,
                _pt_filechooser_display_mode = "list_image_meta",
            }
            for k, v in pairs(CoverMenu) do menu[k] = v end

            menu:setupLayout()

            UIManager.scheduleIn = original_schedule_in
            BookInfoManager.getSetting = original_get_setting

            assert.is_number(scheduled_delay)
            assert.is_true(scheduled_delay > 0 and scheduled_delay <= 60)
            assert.is_function(scheduled_callback)
            assert.is_not_nil(menu.file_chooser.footer_refresh_action)
        end)

        it("refreshes the footer immediately after setup so device info is visible on first show", function()
            local UIManager = package.loaded["ui/uimanager"]
            local ptutil = package.loaded["ptutil"]
            local filemanagerutil = package.loaded["apps/filemanager/filemanagerutil"]
            local filemanagershortcuts = package.loaded["apps/filemanager/filemanagershortcuts"]
            local original_schedule_in = UIManager.scheduleIn
            local original_get_setting = BookInfoManager.getSetting
            local original_format_footer_text = ptutil.formatFooterText
            local original_get_default_dir = filemanagerutil.getDefaultDir
            local original_has_folder_shortcut = filemanagershortcuts.hasFolderShortcut

            UIManager.scheduleIn = function() end
            ptutil.formatFooterText = function()
                return "Clock Wi-Fi Battery"
            end
            filemanagerutil.getDefaultDir = function()
                return "/default"
            end
            filemanagershortcuts.hasFolderShortcut = function()
                return false
            end
            BookInfoManager.getSetting = function(_, key)
                if key == "replace_footer_text" then
                    return true
                end
                return original_get_setting(BookInfoManager, key)
            end

            local menu = {
                show_parent = {},
                root_path = "/books",
                onHome = function() end,
                registerKeyEvents = function() end,
                _pt_filechooser_display_mode = "list_image_meta",
            }
            for k, v in pairs(CoverMenu) do menu[k] = v end

            menu:setupLayout()

            UIManager.scheduleIn = original_schedule_in
            ptutil.formatFooterText = original_format_footer_text
            filemanagerutil.getDefaultDir = original_get_default_dir
            filemanagershortcuts.hasFolderShortcut = original_has_folder_shortcut
            BookInfoManager.getSetting = original_get_setting

            assert.equal("Clock Wi-Fi Battery", menu.file_chooser.cur_folder_text.text)
        end)

        it("does not redraw the footer when the refreshed text is unchanged", function()
            local scheduled_callback
            local dirty_calls = 0
            local set_text_calls = 0
            local UIManager = package.loaded["ui/uimanager"]
            local ptutil = package.loaded["ptutil"]
            local filemanagerutil = package.loaded["apps/filemanager/filemanagerutil"]
            local filemanagershortcuts = package.loaded["apps/filemanager/filemanagershortcuts"]
            local original_schedule_in = UIManager.scheduleIn
            local original_set_dirty = UIManager.setDirty
            local original_format_footer_text = ptutil.formatFooterText
            local original_get_setting = BookInfoManager.getSetting
            local original_get_default_dir = filemanagerutil.getDefaultDir
            local original_has_folder_shortcut = filemanagershortcuts.hasFolderShortcut

            UIManager.scheduleIn = function(_, _, callback)
                scheduled_callback = callback
            end
            UIManager.setDirty = function()
                dirty_calls = dirty_calls + 1
            end
            ptutil.formatFooterText = function()
                return "Footer"
            end
            filemanagerutil.getDefaultDir = function()
                return "/default"
            end
            filemanagershortcuts.hasFolderShortcut = function()
                return false
            end
            BookInfoManager.getSetting = function(_, key)
                if key == "replace_footer_text" then
                    return true
                end
                return original_get_setting(BookInfoManager, key)
            end

            local menu = {
                show_parent = {},
                root_path = "/test",
                onHome = function() end,
                registerKeyEvents = function() end,
                _pt_filechooser_display_mode = "list_image_meta",
            }
            for k, v in pairs(CoverMenu) do menu[k] = v end

            menu:setupLayout()
            menu.file_chooser.path = "/books"
            menu.file_chooser.cur_folder_text.text = "Footer"
            menu.file_chooser.cur_folder_text.setText = function(_, _)
                set_text_calls = set_text_calls + 1
            end
            menu.file_chooser.cur_folder_text.setMaxWidth = function() end
            dirty_calls = 0

            scheduled_callback()

            UIManager.scheduleIn = original_schedule_in
            UIManager.setDirty = original_set_dirty
            ptutil.formatFooterText = original_format_footer_text
            BookInfoManager.getSetting = original_get_setting
            filemanagerutil.getDefaultDir = original_get_default_dir
            filemanagershortcuts.hasFolderShortcut = original_has_folder_shortcut

            assert.equal(0, set_text_calls)
            assert.equal(0, dirty_calls)
        end)

        it("refreshes the footer when the frontlight state changes", function()
            local dirty_calls = 0
            local footer_text = "Warmth 10%"
            local UIManager = package.loaded["ui/uimanager"]
            local ptutil = package.loaded["ptutil"]
            local filemanagerutil = package.loaded["apps/filemanager/filemanagerutil"]
            local filemanagershortcuts = package.loaded["apps/filemanager/filemanagershortcuts"]
            local original_schedule_in = UIManager.scheduleIn
            local original_set_dirty = UIManager.setDirty
            local original_format_footer_text = ptutil.formatFooterText
            local original_get_setting = BookInfoManager.getSetting
            local original_get_default_dir = filemanagerutil.getDefaultDir
            local original_has_folder_shortcut = filemanagershortcuts.hasFolderShortcut

            UIManager.scheduleIn = function() end
            UIManager.setDirty = function()
                dirty_calls = dirty_calls + 1
            end
            ptutil.formatFooterText = function()
                return footer_text
            end
            filemanagerutil.getDefaultDir = function()
                return "/default"
            end
            filemanagershortcuts.hasFolderShortcut = function()
                return false
            end
            BookInfoManager.getSetting = function(_, key)
                if key == "replace_footer_text" then
                    return true
                end
                return original_get_setting(BookInfoManager, key)
            end

            local menu = {
                show_parent = {},
                root_path = "/books",
                onHome = function() end,
                registerKeyEvents = function() end,
                _pt_filechooser_display_mode = "list_image_meta",
            }
            for k, v in pairs(CoverMenu) do menu[k] = v end

            menu:setupLayout()
            menu.file_chooser.path = "/books"
            menu.file_chooser.cur_folder_text.text = "Warmth 0%"
            dirty_calls = 0
            footer_text = "Warmth 10%"

            menu.file_chooser:onFrontlightStateChanged()

            UIManager.scheduleIn = original_schedule_in
            UIManager.setDirty = original_set_dirty
            ptutil.formatFooterText = original_format_footer_text
            BookInfoManager.getSetting = original_get_setting
            filemanagerutil.getDefaultDir = original_get_default_dir
            filemanagershortcuts.hasFolderShortcut = original_has_folder_shortcut

            assert.equal("Warmth 10%", menu.file_chooser.cur_folder_text.text)
            assert.equal(1, dirty_calls)
        end)

        it("does not repaint the footer when the topmost widget covers the screen", function()
            local dirty_calls = 0
            local footer_text = "Warmth 25%"
            local UIManager = package.loaded["ui/uimanager"]
            local ptutil = package.loaded["ptutil"]
            local filemanagerutil = package.loaded["apps/filemanager/filemanagerutil"]
            local filemanagershortcuts = package.loaded["apps/filemanager/filemanagershortcuts"]
            local original_schedule_in = UIManager.scheduleIn
            local original_set_dirty = UIManager.setDirty
            local original_get_topmost = UIManager.getTopmostVisibleWidget
            local original_format_footer_text = ptutil.formatFooterText
            local original_get_setting = BookInfoManager.getSetting
            local original_get_default_dir = filemanagerutil.getDefaultDir
            local original_has_folder_shortcut = filemanagershortcuts.hasFolderShortcut

            UIManager.scheduleIn = function() end
            UIManager.setDirty = function()
                dirty_calls = dirty_calls + 1
            end
            UIManager.getTopmostVisibleWidget = function()
                return { covers_fullscreen = true }
            end
            ptutil.formatFooterText = function()
                return footer_text
            end
            filemanagerutil.getDefaultDir = function()
                return "/default"
            end
            filemanagershortcuts.hasFolderShortcut = function()
                return false
            end
            BookInfoManager.getSetting = function(_, key)
                if key == "replace_footer_text" then
                    return true
                end
                return original_get_setting(BookInfoManager, key)
            end

            local menu = {
                show_parent = { name = "FileManager" },
                root_path = "/books",
                onHome = function() end,
                registerKeyEvents = function() end,
                _pt_filechooser_display_mode = "list_image_meta",
            }
            for k, v in pairs(CoverMenu) do menu[k] = v end

            menu:setupLayout()
            menu.file_chooser.path = "/books"
            menu.file_chooser.cur_folder_text.text = "Warmth 0%"
            dirty_calls = 0

            menu.file_chooser:onFrontlightStateChanged()

            UIManager.scheduleIn = original_schedule_in
            UIManager.setDirty = original_set_dirty
            UIManager.getTopmostVisibleWidget = original_get_topmost
            ptutil.formatFooterText = original_format_footer_text
            BookInfoManager.getSetting = original_get_setting
            filemanagerutil.getDefaultDir = original_get_default_dir
            filemanagershortcuts.hasFolderShortcut = original_has_folder_shortcut

            assert.equal("Warmth 25%", menu.file_chooser.cur_folder_text.text)
            assert.equal(0, dirty_calls)
        end)

        it("requests a full repaint when another visible widget may overlap the footer", function()
            local dirty_widget
            local dirty_payload
            local footer_text = "Warmth 30%"
            local UIManager = package.loaded["ui/uimanager"]
            local ptutil = package.loaded["ptutil"]
            local filemanagerutil = package.loaded["apps/filemanager/filemanagerutil"]
            local filemanagershortcuts = package.loaded["apps/filemanager/filemanagershortcuts"]
            local original_schedule_in = UIManager.scheduleIn
            local original_set_dirty = UIManager.setDirty
            local original_get_topmost = UIManager.getTopmostVisibleWidget
            local original_format_footer_text = ptutil.formatFooterText
            local original_get_setting = BookInfoManager.getSetting
            local original_get_default_dir = filemanagerutil.getDefaultDir
            local original_has_folder_shortcut = filemanagershortcuts.hasFolderShortcut

            UIManager.scheduleIn = function() end
            UIManager.setDirty = function(_, widget, payload)
                dirty_widget = widget
                dirty_payload = payload
            end
            UIManager.getTopmostVisibleWidget = function()
                return { name = "Dialog" }
            end
            ptutil.formatFooterText = function()
                return footer_text
            end
            filemanagerutil.getDefaultDir = function()
                return "/default"
            end
            filemanagershortcuts.hasFolderShortcut = function()
                return false
            end
            BookInfoManager.getSetting = function(_, key)
                if key == "replace_footer_text" then
                    return true
                end
                return original_get_setting(BookInfoManager, key)
            end

            local menu = {
                show_parent = { name = "FileManager" },
                root_path = "/books",
                onHome = function() end,
                registerKeyEvents = function() end,
                _pt_filechooser_display_mode = "list_image_meta",
            }
            for k, v in pairs(CoverMenu) do menu[k] = v end

            menu:setupLayout()
            menu.file_chooser.path = "/books"
            menu.file_chooser.cur_folder_text.text = "Warmth 0%"
            dirty_widget = nil
            dirty_payload = nil

            menu.file_chooser:onFrontlightStateChanged()

            UIManager.scheduleIn = original_schedule_in
            UIManager.setDirty = original_set_dirty
            UIManager.getTopmostVisibleWidget = original_get_topmost
            ptutil.formatFooterText = original_format_footer_text
            BookInfoManager.getSetting = original_get_setting
            filemanagerutil.getDefaultDir = original_get_default_dir
            filemanagershortcuts.hasFolderShortcut = original_has_folder_shortcut

            assert.equal("Warmth 30%", menu.file_chooser.cur_folder_text.text)
            assert.is_nil(dirty_widget)
            assert.equal("ui", dirty_payload)
        end)

        it("unschedules footer refreshes on suspend", function()
            local unscheduled_action
            local UIManager = package.loaded["ui/uimanager"]
            local original_unschedule = UIManager.unschedule

            UIManager.unschedule = function(_, action)
                unscheduled_action = action
            end

            local menu = {
                footer_refresh_action = "footer-refresh",
            }
            for k, v in pairs(CoverMenu) do menu[k] = v end

            menu:onSuspend()

            UIManager.unschedule = original_unschedule

            assert.equal("footer-refresh", unscheduled_action)
            assert.is_nil(menu.footer_refresh_action)
        end)

        it("defers resume footer refresh until out of screensaver when delayed screensaver is enabled", function()
            local refresh_calls = 0
            local schedule_calls = 0
            local original_read_setting = G_reader_settings.readSetting

            G_reader_settings.readSetting = function(_, key)
                if key == "screensaver_delay" then
                    return "3"
                end
                return original_read_setting(G_reader_settings, key)
            end

            local menu = {}
            for k, v in pairs(CoverMenu) do menu[k] = v end
            menu.refreshFooterText = function()
                refresh_calls = refresh_calls + 1
            end
            menu.scheduleFooterRefresh = function()
                schedule_calls = schedule_calls + 1
            end

            menu:onResume()
            menu:onOutOfScreenSaver()

            G_reader_settings.readSetting = original_read_setting

            assert.equal(1, refresh_calls)
            assert.equal(1, schedule_calls)
            assert.is_nil(menu._pt_footer_resume_delayed)
        end)

        it("refreshes the footer immediately on resume when no delayed screensaver is configured", function()
            local refresh_calls = 0
            local schedule_calls = 0
            local original_read_setting = G_reader_settings.readSetting

            G_reader_settings.readSetting = function(_, key)
                if key == "screensaver_delay" then
                    return "disable"
                end
                return original_read_setting(G_reader_settings, key)
            end

            local menu = {}
            for k, v in pairs(CoverMenu) do menu[k] = v end
            menu.refreshFooterText = function()
                refresh_calls = refresh_calls + 1
            end
            menu.scheduleFooterRefresh = function()
                schedule_calls = schedule_calls + 1
            end

            menu:onResume()

            G_reader_settings.readSetting = original_read_setting

            assert.equal(1, refresh_calls)
            assert.equal(1, schedule_calls)
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

        it("can require hold for the up folder button", function()
            local original_get_setting = BookInfoManager.getSetting
            BookInfoManager.getSetting = function(_, key)
                if key == "folder_up_requires_hold" then
                    return "Y"
                end
                return original_get_setting(BookInfoManager, key)
            end

            local menu = {
                show_parent = {},
                root_path = "/test",
                registerKeyEvents = function() end,
                file_chooser = { path = "/test" }
            }
            for k, v in pairs(CoverMenu) do menu[k] = v end

            menu:setupLayout()

            assert.equal("go_up", menu.title_bar.right2_icon)
            assert.is_false(menu.title_bar.right2_icon_tap_callback)
            assert.is_function(menu.title_bar.right2_icon_hold_callback)
            BookInfoManager.getSetting = original_get_setting
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

        it("toggles KOReader's native flat view by holding the center icon", function()
            local toggled_mode
            local menu = {
                show_parent = {},
                root_path = "/test",
                registerKeyEvents = function() end,
                file_chooser = { path = "/test" },
            }
            for k, v in pairs(CoverMenu) do menu[k] = v end

            menu:setupLayout()
            menu.file_chooser.toggleShowFilesMode = function(_, mode)
                toggled_mode = mode
            end
            menu.title_bar.center_icon_hold_callback()

            assert.equal("show_flat_view", toggled_mode)
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

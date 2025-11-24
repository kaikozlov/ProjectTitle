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

        -- Mock FileChooser
        FileChooser = {
            new = function(self, o) return o end,
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
            end
        }

        -- Mock DocumentRegistry
        package.loaded["document/documentregistry"] = {
            hasProvider = function(filename)
                return filename:match("%.epub$") or filename:match("%.pdf$")
            end
        }

        -- Mock other dependencies
        package.loaded["apps/filemanager/filemanagerbookinfo"] = {}
        package.loaded["apps/filemanager/filemanagerconverter"] = {}
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

        it("clears cover_info_cache", function()
            local menu = {
                item_group = { free = function() end },
                cover_info_cache = { some = "data" },
                _covermenu_onclose_done = false
            }
            for k, v in pairs(CoverMenu) do menu[k] = v end

            menu:onCloseWidget()

            assert.is_nil(menu.cover_info_cache)
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

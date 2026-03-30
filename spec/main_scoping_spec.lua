require 'busted.runner'()
local setup_mocks = require("spec.support.mock_ui")

describe("Main Menu Scoping", function()
    local SAFE_VERSION = 202603000000
    local CoverBrowser
    local CoverMenu

    setup(function()
        if not _G.unpack then _G.unpack = table.unpack end
        setup_mocks()

        package.loaded["ui/uimanager"] = {
            nextTick = function(self, callback)
                if type(self) == "function" then
                    callback = self
                end
                if callback then callback() end
            end,
            show = function() end,
            close = function() end,
        }
        package.loaded["ui/widget/infomessage"] = {
            new = function(o) return o end,
        }
        package.loaded["version"] = {
            getNormalizedCurrentVersion = function() return SAFE_VERSION, "commit" end,
        }
        package.loaded["ui/widget/bookstatuswidget"] = {}
        package.loaded["altbookstatuswidget"] = {}
        package.loaded["dispatcher"] = { registerAction = function() end }
        package.loaded["ui/trapper"] = {}
        package.loaded["ui/widget/booklist"] = {}
        package.loaded["document/documentregistry"] = {}
        package.loaded["apps/filemanager/filemanagerbookinfo"] = {}
        package.loaded["apps/filemanager/filemanagerconverter"] = {}
        package.loaded["apps/filemanager/filemanagershortcuts"] = {
            hasFolderShortcut = function() return false end,
        }
        package.loaded["apps/filemanager/filemanagermenu"] = {
            new = function(self, o) return o or {} end,
        }
        package.loaded["ui/widget/buttondialog"] = {}
        package.loaded["titlebar"] = {
            new = function(self, o) return o or {} end,
        }

        local filechooser = {
            _recalculateDimen = function() end,
            updateItems = function() end,
            onCloseWidget = function() end,
            genItemTable = function() end,
            switchItemTable = function() end,
        }
        package.loaded["ui/widget/filechooser"] = filechooser

        package.loaded["apps/filemanager/filemanager"] = {
            setupLayout = function() end,
            addFileDialogButtons = function() end,
            removeFileDialogButtons = function() end,
        }

        local history_update_called = false
        package.loaded["apps/filemanager/filemanagerhistory"] = {
            updateItemTable = function()
                history_update_called = true
            end,
            _history_update_called = function()
                return history_update_called
            end,
        }
        package.loaded["apps/filemanager/filemanagercollection"] = {
            updateItemTable = function() end,
        }
        package.loaded["apps/filemanager/filemanagerfilesearcher"] = {
            updateItemTable = function() end,
        }

        package.loaded["ui/widget/menu"] = {
            init = function(self)
                self._menu_init_original = true
            end,
            updatePageInfo = function(self)
                self._menu_page_info_original = true
            end,
        }

        _G.G_reader_settings = {
            readSetting = function(self, key)
                if key == "plugins_disabled" then return { coverbrowser = true } end
                return nil
            end,
            isTrue = function() return false end,
            saveSetting = function() end,
        }

        package.loaded["main"] = nil
        package.loaded["covermenu"] = nil
        CoverBrowser = require("main")
        CoverMenu = require("covermenu")
        local BookInfoManager = require("bookinfomanager")
        BookInfoManager.closeDbConnection = function() end
    end)

    it("does not replace shared Menu methods when enabling file manager mode", function()
        local Menu = package.loaded["ui/widget/menu"]
        local original_init = Menu.init
        local original_update_page_info = Menu.updatePageInfo

        CoverBrowser.ui = {
            file_chooser = {
                _recalculateDimen = function() end,
                switchItemTable = function() end,
            },
        }
        CoverBrowser.refreshFileManagerInstance = function() end

        CoverBrowser:setupFileManagerDisplayMode("mosaic_image")

        assert.equal(original_init, Menu.init)
        assert.equal(original_update_page_info, Menu.updatePageInfo)
    end)

    it("does not replace shared FileChooser methods when enabling file manager mode", function()
        local original_update_items = package.loaded["ui/widget/filechooser"].updateItems
        local original_on_close_widget = package.loaded["ui/widget/filechooser"].onCloseWidget
        local original_gen_item_table = package.loaded["ui/widget/filechooser"].genItemTable
        local original_recalculate_dimen = package.loaded["ui/widget/filechooser"]._recalculateDimen

        CoverBrowser.ui = {
            file_chooser = {
                _recalculateDimen = function() end,
                switchItemTable = function() end,
            },
        }
        CoverBrowser.refreshFileManagerInstance = function() end

        CoverBrowser:setupFileManagerDisplayMode("mosaic_image")

        assert.equal(original_update_items, package.loaded["ui/widget/filechooser"].updateItems)
        assert.equal(original_on_close_widget, package.loaded["ui/widget/filechooser"].onCloseWidget)
        assert.equal(original_gen_item_table, package.loaded["ui/widget/filechooser"].genItemTable)
        assert.equal(original_recalculate_dimen, package.loaded["ui/widget/filechooser"]._recalculateDimen)
    end)

    it("patches FileChooser behavior only on the owned file manager instance", function()
        local update_item_table = CoverBrowser.getUpdateItemTableFunc("mosaic_image")
        local file_chooser = {
            updateItems = function() end,
            onCloseWidget = function() end,
            genItemTable = function() end,
            _recalculateDimen = function() end,
            switchItemTable = function() end,
        }
        CoverBrowser.ui = {
            file_chooser = file_chooser,
        }
        CoverBrowser.refreshFileManagerInstance = function() end

        CoverBrowser:setupFileManagerDisplayMode("mosaic_image")
        update_item_table({
            booklist_menu = {
                name = "history",
            },
        })

        assert.equal(CoverMenu.updateItems, file_chooser.updateItems)
        assert.equal(CoverMenu.onCloseWidget, file_chooser.onCloseWidget)
        assert.equal(CoverMenu.genItemTable, file_chooser.genItemTable)
    end)

    it("uses shared menu wiring for owned and hijacked menu instances", function()
        assert.is_function(CoverMenu.configureDisplayMenu)

        local update_item_table = CoverBrowser.getUpdateItemTableFunc("list_no_meta")
        local file_chooser = {
            updateItems = function() end,
            onCloseWidget = function() end,
            genItemTable = function() end,
            _recalculateDimen = function() end,
            switchItemTable = function() end,
        }
        local widget = {
            booklist_menu = {
                name = "history",
            },
        }

        CoverBrowser.ui = {
            file_chooser = file_chooser,
        }
        CoverBrowser.refreshFileManagerInstance = function() end

        CoverBrowser:setupFileManagerDisplayMode("list_no_meta")
        update_item_table(widget)

        assert.equal(file_chooser.display_mode_type, widget.booklist_menu.display_mode_type)
        assert.equal(file_chooser.updateItems, widget.booklist_menu.updateItems)
        assert.equal(file_chooser.onCloseWidget, widget.booklist_menu.onCloseWidget)
        assert.equal(file_chooser.updatePageInfo, widget.booklist_menu.updatePageInfo)
        assert.equal(file_chooser._recalculateDimen, widget.booklist_menu._recalculateDimen)
        assert.equal(file_chooser._updateItemsBuildUI, widget.booklist_menu._updateItemsBuildUI)
        assert.equal(file_chooser._do_cover_images, widget.booklist_menu._do_cover_images)
        assert.equal(file_chooser._do_filename_only, widget.booklist_menu._do_filename_only)
        assert.equal(file_chooser._do_hint_opened, widget.booklist_menu._do_hint_opened)
    end)

    it("patches updatePageInfo only on the owned widget instance", function()
        local Menu = package.loaded["ui/widget/menu"]
        local original_update_page_info = Menu.updatePageInfo
        local update_item_table = CoverBrowser.getUpdateItemTableFunc("list_image_meta")
        local widget = {
            booklist_menu = {
                name = "history",
            },
        }

        update_item_table(widget)

        assert.equal(CoverMenu.updatePageInfo, widget.booklist_menu.updatePageInfo)
        assert.equal(original_update_page_info, Menu.updatePageInfo)
        assert.is_true(package.loaded["apps/filemanager/filemanagerhistory"]._history_update_called())
    end)

    it("initializes widget_pool and render_context on hijacked BookList menus", function()
        local update_item_table = CoverBrowser.getUpdateItemTableFunc("list_image_meta")
        local widget = {
            booklist_menu = {
                name = "history",
            },
        }

        update_item_table(widget)

        assert.is_table(widget.booklist_menu.widget_pool)
        assert.is_table(widget.booklist_menu.render_context)
    end)

    it("reconfigures a rebuilt file chooser even when the saved mode has not changed", function()
        local original_is_true = _G.G_reader_settings.isTrue
        _G.G_reader_settings.isTrue = function(_, key)
            if key == "aaaProjectTitle_initial_default_setup_done2" then
                return true
            end
            return false
        end

        local refresh_calls = 0
        CoverBrowser.refreshFileManagerInstance = function()
            refresh_calls = refresh_calls + 1
        end

        CoverBrowser.ui = {
            document = nil,
            menu = { registerToMainMenu = function() end },
            file_chooser = {
                updateItems = function() end,
                onCloseWidget = function() end,
                genItemTable = function() end,
                _recalculateDimen = function() end,
                switchItemTable = function() end,
            },
        }

        local BookInfoManager = require("bookinfomanager")
        BookInfoManager:saveSetting("config_version", "7")
        BookInfoManager:saveSetting("filemanager_display_mode", "list_image_meta")
        BookInfoManager:saveSetting("history_display_mode", "list_image_meta")
        BookInfoManager:saveSetting("collection_display_mode", "list_image_meta")

        CoverBrowser:init()

        local rebuilt_file_chooser = {
            updateItems = function() end,
            onCloseWidget = function() end,
            genItemTable = function() end,
            _recalculateDimen = function() end,
            switchItemTable = function() end,
        }
        CoverBrowser.ui.file_chooser = rebuilt_file_chooser

        CoverBrowser:setupFileManagerDisplayMode("list_image_meta")

        _G.G_reader_settings.isTrue = original_is_true

        assert.equal(CoverMenu.updateItems, rebuilt_file_chooser.updateItems)
        assert.equal(CoverMenu.onCloseWidget, rebuilt_file_chooser.onCloseWidget)
        assert.equal(CoverMenu.genItemTable, rebuilt_file_chooser.genItemTable)
        assert.equal("list", rebuilt_file_chooser.display_mode_type)
        assert.is_true(refresh_calls >= 1)
    end)

    it("reconfigures the history widget when the saved mode is unchanged but its hook was lost", function()
        local original_is_true = _G.G_reader_settings.isTrue
        _G.G_reader_settings.isTrue = function(_, key)
            if key == "aaaProjectTitle_initial_default_setup_done2" then
                return true
            end
            return false
        end

        local BookInfoManager = require("bookinfomanager")
        BookInfoManager:saveSetting("config_version", "7")
        BookInfoManager:saveSetting("filemanager_display_mode", "list_image_meta")
        BookInfoManager:saveSetting("history_display_mode", "list_image_meta")
        BookInfoManager:saveSetting("collection_display_mode", "list_image_meta")

        CoverBrowser.ui = {
            document = nil,
            menu = { registerToMainMenu = function() end },
            file_chooser = {
                updateItems = function() end,
                onCloseWidget = function() end,
                genItemTable = function() end,
                _recalculateDimen = function() end,
                switchItemTable = function() end,
            },
        }
        CoverBrowser.refreshFileManagerInstance = function() end

        local history_widget = package.loaded["apps/filemanager/filemanagerhistory"]

        CoverBrowser:init()

        local lost_update_item_table = function() end
        history_widget.updateItemTable = lost_update_item_table
        history_widget._pt_widget_display_mode = nil

        CoverBrowser.setupWidgetDisplayMode("history", "list_image_meta")

        _G.G_reader_settings.isTrue = original_is_true

        assert.is_not_equal(lost_update_item_table, history_widget.updateItemTable)
        assert.equal("list_image_meta", history_widget._pt_widget_display_mode)
    end)

    it("reconfigures the collections widget when the saved mode is unchanged but its hook was lost", function()
        local original_is_true = _G.G_reader_settings.isTrue
        _G.G_reader_settings.isTrue = function(_, key)
            if key == "aaaProjectTitle_initial_default_setup_done2" then
                return true
            end
            return false
        end

        local BookInfoManager = require("bookinfomanager")
        BookInfoManager:saveSetting("config_version", "7")
        BookInfoManager:saveSetting("filemanager_display_mode", "list_image_meta")
        BookInfoManager:saveSetting("history_display_mode", "list_image_meta")
        BookInfoManager:saveSetting("collection_display_mode", "list_image_meta")

        CoverBrowser.ui = {
            document = nil,
            menu = { registerToMainMenu = function() end },
            file_chooser = {
                updateItems = function() end,
                onCloseWidget = function() end,
                genItemTable = function() end,
                _recalculateDimen = function() end,
                switchItemTable = function() end,
            },
        }
        CoverBrowser.refreshFileManagerInstance = function() end

        local collection_widget = package.loaded["apps/filemanager/filemanagercollection"]

        CoverBrowser:init()

        local lost_update_item_table = function() end
        collection_widget.updateItemTable = lost_update_item_table
        collection_widget._pt_widget_display_mode = nil

        CoverBrowser.setupWidgetDisplayMode("collections", "list_image_meta")

        _G.G_reader_settings.isTrue = original_is_true

        assert.is_not_equal(lost_update_item_table, collection_widget.updateItemTable)
        assert.equal("list_image_meta", collection_widget._pt_widget_display_mode)
    end)

    it("keeps file manager wiring coherent across mode toggles", function()
        local file_chooser = {
            updateItems = function() end,
            onCloseWidget = function() end,
            genItemTable = function() end,
            _recalculateDimen = function() end,
            switchItemTable = function() end,
        }
        CoverBrowser.ui = {
            file_chooser = file_chooser,
        }
        CoverBrowser.refreshFileManagerInstance = function() end

        CoverBrowser:setupFileManagerDisplayMode("list_image_meta")
        assert.equal("list", file_chooser.display_mode_type)
        assert.equal(CoverMenu.updateItems, file_chooser.updateItems)
        assert.equal(CoverMenu.genItemTable, file_chooser.genItemTable)

        CoverBrowser:setupFileManagerDisplayMode("mosaic_image")
        assert.equal("mosaic", file_chooser.display_mode_type)
        assert.equal(CoverMenu.updateItems, file_chooser.updateItems)
        assert.equal(CoverMenu.genItemTable, file_chooser.genItemTable)

        CoverBrowser:setupFileManagerDisplayMode(nil)
        assert.is_nil(file_chooser.display_mode_type)
        assert.equal(package.loaded["ui/widget/filechooser"].updateItems, file_chooser.updateItems)
        assert.equal(package.loaded["ui/widget/filechooser"].genItemTable, file_chooser.genItemTable)
    end)
end)

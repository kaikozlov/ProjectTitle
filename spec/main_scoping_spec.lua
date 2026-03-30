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
end)

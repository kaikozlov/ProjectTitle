require 'busted.runner'()
local setup_mocks = require("spec.support.mock_ui")

describe("Main Menu Scoping", function()
    local SAFE_VERSION = 202607000000
    local CoverBrowser
    local CoverMenu
    local PathChooser, FileManager
    local stock_pathchooser_init, stock_filemanager_setuplayout

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
            init = function(self)
                self.title_bar = self.title_bar or { title = self.title or "" }
                if self._run_filechooser_init then
                    self:_run_filechooser_init()
                end
            end,
            _recalculateDimen = function() end,
            updateItems = function() end,
            onCloseWidget = function() end,
            genItemTable = function() end,
            switchItemTable = function() end,
        }
        package.loaded["ui/widget/filechooser"] = filechooser
        package.loaded["ui/widget/pathchooser"] = {
            init = function(self)
                if self.title == true then
                    if self.select_directory and not self.select_file then
                        self.title = "Long-press folder's name to choose it"
                    elseif not self.select_directory and self.select_file then
                        self.title = "Long-press file's name to choose it"
                    else
                        self.title = "Long-press item's name to choose it"
                    end
                end
                filechooser.init(self)
                self._pathchooser_init_original = true
            end,
        }

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
        BookInfoManager.terminateBackgroundJobs = function() end
        BookInfoManager.cleanUp = function() end

        -- main.lua captured these stock hooks at require time just now; specs
        -- that enable a rich mode leave ProjectTitle's wrappers installed, so
        -- remember the stock pair here and restore after every spec.
        PathChooser = package.loaded["ui/widget/pathchooser"]
        FileManager = package.loaded["apps/filemanager/filemanager"]
        stock_pathchooser_init = PathChooser.init
        stock_filemanager_setuplayout = FileManager.setupLayout
    end)

    after_each(function()
        PathChooser.init = stock_pathchooser_init
        FileManager.setupLayout = stock_filemanager_setuplayout
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

    it("replaces shared PathChooser init when enabling file manager mode", function()
        local PathChooser = package.loaded["ui/widget/pathchooser"]
        local original_init = PathChooser.init

        CoverBrowser.ui = {
            file_chooser = {
                _recalculateDimen = function() end,
                switchItemTable = function() end,
            },
        }
        CoverBrowser.refreshFileManagerInstance = function() end

        CoverBrowser:setupFileManagerDisplayMode("mosaic_image")

        assert.is_not_equal(original_init, PathChooser.init)
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

    it("marks the owned file manager instance as non-pathchooser during activation", function()
        local file_chooser = {
            title_bar = { title = "Home" },
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

        local context = CoverMenu.buildRenderContext(file_chooser)

        assert.is_false(context.is_pathchooser)
    end)

    it("configures PathChooser instances through the wrapped init", function()
        local PathChooser = package.loaded["ui/widget/pathchooser"]
        local finish_calls = 0
        local original_finish = CoverMenu.finishMenuInit

        CoverBrowser.ui = {
            file_chooser = {
                _recalculateDimen = function() end,
                switchItemTable = function() end,
            },
        }
        CoverBrowser.refreshFileManagerInstance = function() end
        CoverBrowser:setupFileManagerDisplayMode("list_image_meta")

        CoverMenu.finishMenuInit = function(self)
            finish_calls = finish_calls + 1
        end

        local chooser = {
            name = "pathchooser",
            title_bar = { title = "Choose folder" },
            switchItemTable = function() end,
        }
        PathChooser.init(chooser)

        CoverMenu.finishMenuInit = original_finish

        assert.is_true(chooser._pathchooser_init_original)
        assert.equal(CoverMenu.updateItems, chooser.updateItems)
        assert.equal(CoverMenu.onCloseWidget, chooser.onCloseWidget)
        assert.equal(CoverMenu.genItemTable, chooser.genItemTable)
        assert.equal("list", chooser.display_mode_type)
        assert.equal(1, finish_calls)
    end)

    it("reuses the wrapped PathChooser state for later render contexts", function()
        local PathChooser = package.loaded["ui/widget/pathchooser"]
        local original_finish = CoverMenu.finishMenuInit

        CoverBrowser.ui = {
            file_chooser = {
                _recalculateDimen = function() end,
                switchItemTable = function() end,
            },
        }
        CoverBrowser.refreshFileManagerInstance = function() end
        CoverBrowser:setupFileManagerDisplayMode("list_image_meta")

        CoverMenu.finishMenuInit = function() end

        local chooser = {
            name = "pathchooser",
            title_bar = { title = "Choose folder" },
            switchItemTable = function() end,
        }
        PathChooser.init(chooser)
        chooser.title_bar.title = ""

        local context = CoverMenu.buildRenderContext(chooser)

        CoverMenu.finishMenuInit = original_finish

        assert.is_true(context.is_pathchooser)
    end)

    it("keeps the up-folder entry on the first PathChooser render", function()
        local PathChooser = package.loaded["ui/widget/pathchooser"]
        local original_gen_item_table = CoverMenu._FileChooser_genItemTable_orig
        local original_finish = CoverMenu.finishMenuInit

        CoverBrowser.ui = {
            file_chooser = {
                _recalculateDimen = function() end,
                switchItemTable = function() end,
            },
        }
        CoverBrowser.refreshFileManagerInstance = function() end
        CoverBrowser:setupFileManagerDisplayMode("list_image_meta")

        CoverMenu._FileChooser_genItemTable_orig = function()
            return {
                { text = "Current folder helper", path = "/books/.", bold = true },
                { text = "⬆ ../", path = "/books/..", is_go_up = true },
                { text = "file1.epub", path = "/books/file1.epub", is_file = true },
            }
        end
        CoverMenu.finishMenuInit = function() end

        local chooser = {
            name = "pathchooser",
            title = true,
            path = "/books",
            select_directory = true,
            select_file = false,
            _run_filechooser_init = function(self)
                self._initial_item_table = self:genItemTable({}, {}, self.path)
            end,
        }

        PathChooser.init(chooser)
        CoverMenu._FileChooser_genItemTable_orig = original_gen_item_table
        CoverMenu.finishMenuInit = original_finish

        assert.equal(3, #chooser._initial_item_table)
        assert.is_true(chooser._initial_item_table[2].is_go_up)
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

    it("rebuilds the live file manager with the stock layout when returning to classic mode", function()
        local FileChooser = package.loaded["ui/widget/filechooser"]
        local file_chooser = {
            updateItems = function() end,
            onCloseWidget = function() end,
            genItemTable = function() end,
            _recalculateDimen = function() end,
            switchItemTable = function() end,
        }
        local layout_rebuilds = 0
        CoverBrowser.ui = {
            file_chooser = file_chooser,
            setupLayout = function(self)
                layout_rebuilds = layout_rebuilds + 1
                self.file_chooser = {
                    stock_layout = true,
                    updateItems = FileChooser.updateItems,
                    onCloseWidget = FileChooser.onCloseWidget,
                    genItemTable = FileChooser.genItemTable,
                    _recalculateDimen = FileChooser._recalculateDimen,
                    switchItemTable = function() end,
                }
            end,
        }
        CoverBrowser.refreshFileManagerInstance = function() end

        CoverBrowser:setupFileManagerDisplayMode("list_image_meta")
        assert.equal("list", file_chooser.display_mode_type)
        assert.equal(CoverMenu.updateItems, file_chooser.updateItems)
        assert.equal(CoverMenu.genItemTable, file_chooser.genItemTable)

        CoverBrowser:setupFileManagerDisplayMode("mosaic_image")
        assert.equal("mosaic", file_chooser.display_mode_type)

        CoverBrowser:setupFileManagerDisplayMode(nil)

        assert.equal(1, layout_rebuilds)
        assert.is_true(CoverBrowser.ui.file_chooser.stock_layout)
        assert.is_not_equal(file_chooser, CoverBrowser.ui.file_chooser)
        assert.equal(FileChooser.updateItems, CoverBrowser.ui.file_chooser.updateItems)
        assert.equal(FileChooser.genItemTable, CoverBrowser.ui.file_chooser.genItemTable)
    end)

    it("restores shared PathChooser init when returning to classic mode", function()
        local PathChooser = package.loaded["ui/widget/pathchooser"]
        local original_init = PathChooser.init

        CoverBrowser.ui = {
            file_chooser = {
                updateItems = function() end,
                onCloseWidget = function() end,
                genItemTable = function() end,
                _recalculateDimen = function() end,
                switchItemTable = function() end,
            },
        }
        CoverBrowser.refreshFileManagerInstance = function() end

        CoverBrowser:setupFileManagerDisplayMode("list_image_meta")
        assert.is_not_equal(original_init, PathChooser.init)

        CoverBrowser:setupFileManagerDisplayMode(nil)
        assert.equal(original_init, PathChooser.init)
    end)

    it("does not clobber later shared hooks when switching between rich modes", function()
        local PathChooser = package.loaded["ui/widget/pathchooser"]
        local FileManager = package.loaded["apps/filemanager/filemanager"]
        local FileChooser = package.loaded["ui/widget/filechooser"]
        local original_pathchooser_init = PathChooser.init
        local original_filemanager_layout = FileManager.setupLayout
        CoverBrowser.ui = {
            file_chooser = {
                updateItems = FileChooser.updateItems,
                onCloseWidget = FileChooser.onCloseWidget,
                genItemTable = FileChooser.genItemTable,
                _recalculateDimen = FileChooser._recalculateDimen,
                switchItemTable = function() end,
            },
        }
        CoverBrowser.refreshFileManagerInstance = function() end

        CoverBrowser:setupFileManagerDisplayMode("list_image_meta")
        local later_pathchooser_hook = function() end
        local later_filemanager_hook = function() end
        PathChooser.init = later_pathchooser_hook
        FileManager.setupLayout = later_filemanager_hook

        CoverBrowser:setupFileManagerDisplayMode("mosaic_image")

        assert.equal(later_pathchooser_hook, PathChooser.init)
        assert.equal(later_filemanager_hook, FileManager.setupLayout)
        PathChooser.init = original_pathchooser_init
        FileManager.setupLayout = original_filemanager_layout
        CoverBrowser:setupFileManagerDisplayMode(nil)
    end)

    it("does not clobber later widget hooks when returning to classic mode", function()
        local FileChooser = package.loaded["ui/widget/filechooser"]
        local history = package.loaded["apps/filemanager/filemanagerhistory"]
        local filesearcher = package.loaded["apps/filemanager/filemanagerfilesearcher"]
        local original_history_update = history.updateItemTable
        local original_filesearcher_update = filesearcher.updateItemTable
        CoverBrowser.ui = {
            file_chooser = {
                updateItems = FileChooser.updateItems,
                onCloseWidget = FileChooser.onCloseWidget,
                genItemTable = FileChooser.genItemTable,
                _recalculateDimen = FileChooser._recalculateDimen,
                switchItemTable = function() end,
            },
        }
        CoverBrowser.refreshFileManagerInstance = function() end

        CoverBrowser:setupFileManagerDisplayMode("list_image_meta")
        CoverBrowser.setupWidgetDisplayMode("history", "list_image_meta")
        local later_history_hook = function() end
        local later_filesearcher_hook = function() end
        history.updateItemTable = later_history_hook
        filesearcher.updateItemTable = later_filesearcher_hook

        CoverBrowser.setupWidgetDisplayMode("history", nil)
        CoverBrowser:setupFileManagerDisplayMode(nil)

        assert.equal(later_history_hook, history.updateItemTable)
        assert.equal(later_filesearcher_hook, filesearcher.updateItemTable)
        history.updateItemTable = original_history_update
        filesearcher.updateItemTable = original_filesearcher_update
    end)

    it("restores instance-scoped overrides when the plugin stops", function()
        local PathChooser = package.loaded["ui/widget/pathchooser"]
        local FileChooser = package.loaded["ui/widget/filechooser"]
        local FileManager = package.loaded["apps/filemanager/filemanager"]
        local BookStatusWidget = package.loaded["ui/widget/bookstatuswidget"]
        local AltBookStatusWidget = package.loaded["altbookstatuswidget"]
        local BookList = package.loaded["ui/widget/booklist"]
        local history = package.loaded["apps/filemanager/filemanagerhistory"]
        local collections = package.loaded["apps/filemanager/filemanagercollection"]
        local filesearcher = package.loaded["apps/filemanager/filemanagerfilesearcher"]
        local BookInfoManager = package.loaded["bookinfomanager"]
        local clear_cover_cache_calls = 0
        local original_clear_cover_cache = BookInfoManager.clearCoverCache
        BookInfoManager.clearCoverCache = function()
            clear_cover_cache_calls = clear_cover_cache_calls + 1
        end
        local original_status_methods = {
            genHeader = function() end,
            getStatusContent = function() end,
            genBookInfoGroup = function() end,
            genSummaryGroup = function() end,
            genStatisticsGroup = function() end,
        }
        local original_title_collate = { marker = "stock-title" }
        local original_authors_collate = { marker = "stock-authors" }
        local original_series_collate = { marker = "stock-series" }
        for name, method in pairs(original_status_methods) do
            BookStatusWidget[name] = method
            AltBookStatusWidget[name] = function() end
        end
        BookList.collates = {
            title = original_title_collate,
            authors = original_authors_collate,
            series = original_series_collate,
        }
        CoverBrowser._installBookStatusOverrides()
        CoverBrowser.addSortMethods()
        local file_chooser = {
            updateItems = FileChooser.updateItems,
            onCloseWidget = FileChooser.onCloseWidget,
            genItemTable = FileChooser.genItemTable,
            _recalculateDimen = FileChooser._recalculateDimen,
            switchItemTable = function() end,
        }

        CoverBrowser.ui = {
            coverbrowser = CoverBrowser,
            projecttitle = CoverBrowser,
            file_chooser = file_chooser,
        }
        CoverBrowser.refreshFileManagerInstance = function() end
        CoverBrowser:setupFileManagerDisplayMode(nil)
        CoverBrowser.setupWidgetDisplayMode("history", nil)
        CoverBrowser.setupWidgetDisplayMode("collections", nil)

        local original_pathchooser_init = PathChooser.init
        local original_filemanager_layout = FileManager.setupLayout
        local original_history_update = history.updateItemTable
        local original_collections_update = collections.updateItemTable
        local original_filesearcher_update = filesearcher.updateItemTable

        CoverBrowser:setupFileManagerDisplayMode("list_image_meta")
        CoverBrowser.setupWidgetDisplayMode("history", "list_image_meta")
        CoverBrowser.setupWidgetDisplayMode("collections", "list_image_meta")
        assert.equal("list_image_meta", history._pt_widget_display_mode)
        assert.is_not_equal(original_history_update, history.updateItemTable)
        assert.is_nil(CoverBrowser._pt_runtime_restored)
        local later_pathchooser_hook = function() end
        local later_filemanager_hook = function() end
        PathChooser.init = later_pathchooser_hook
        FileManager.setupLayout = later_filemanager_hook
        CoverBrowser:stopPlugin()

        assert.equal(FileChooser.updateItems, file_chooser.updateItems)
        assert.equal(FileChooser.onCloseWidget, file_chooser.onCloseWidget)
        assert.equal(FileChooser.genItemTable, file_chooser.genItemTable)
        assert.equal(FileChooser._recalculateDimen, file_chooser._recalculateDimen)
        assert.is_not_equal(original_pathchooser_init, later_pathchooser_hook)
        assert.is_not_equal(original_filemanager_layout, later_filemanager_hook)
        assert.equal(later_pathchooser_hook, PathChooser.init)
        assert.equal(later_filemanager_hook, FileManager.setupLayout)
        assert.equal(original_history_update, history.updateItemTable)
        assert.equal(original_collections_update, collections.updateItemTable)
        assert.equal(original_filesearcher_update, filesearcher.updateItemTable)
        for name, method in pairs(original_status_methods) do
            assert.equal(method, BookStatusWidget[name])
        end
        assert.equal(original_title_collate, BookList.collates.title)
        assert.equal(original_authors_collate, BookList.collates.authors)
        assert.equal(original_series_collate, BookList.collates.series)
        assert.is_nil(BookList.collates.keywords)
        assert.equal(1, clear_cover_cache_calls)
        BookInfoManager.clearCoverCache = original_clear_cover_cache
        assert.is_nil(CoverBrowser.ui.coverbrowser)
        assert.is_nil(CoverBrowser.ui.projecttitle)
    end)
end)

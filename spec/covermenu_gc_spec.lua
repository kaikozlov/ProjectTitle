require 'busted.runner'()
local setup_mocks = require("spec.support.mock_ui")

describe("CoverMenu Garbage Collection", function()
    local CoverMenu

    local function build_menu(menu)
        for k, v in pairs(CoverMenu) do
            menu[k] = v
        end
        return menu
    end

    local function make_dimen()
        return {
            w = 100,
            h = 100,
            copy = function(self)
                return {
                    w = self.w,
                    h = self.h,
                    combine = function(_, other) return other end,
                }
            end,
        }
    end

    before_each(function()
        setup_mocks()
        package.loaded["ui/widget/booklist"] = {}
        package.loaded["document/documentregistry"] = {}
        package.loaded["ui/widget/filechooser"] = {
            new = function(self, o) return o end,
        }
        package.loaded["apps/filemanager/filemanagerbookinfo"] = {}
        package.loaded["apps/filemanager/filemanagerconverter"] = {}
        package.loaded["apps/filemanager/filemanager"] = {
            instance = {
                file_chooser = {},
                menu = {},
            },
        }
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
        package.loaded["ui/widget/infomessage"] = {
            new = function(self, o) return o or {} end,
        }
        package.loaded["ui/uimanager"] = {
            nextTick = function(self, callback)
                if type(self) == "function" then
                    callback = self
                end
                if callback then callback() end
            end,
            scheduleIn = function() end,
            unschedule = function() end,
            setDirty = function() end,
            show = function() end,
        }
        package.loaded["ui/widget/menu"] = {
            onCloseWidget = function() end,
            mergeTitleBarIntoLayout = function() end,
        }
        package.loaded["covermenu"] = nil
        CoverMenu = require("covermenu")
        CoverMenu._Menu_updatePageInfo_orig = function() end
        local BookInfoManager = require("bookinfomanager")
        BookInfoManager.terminateBackgroundJobs = function() end
        BookInfoManager.closeDbConnection = function() end
        BookInfoManager.cleanUp = function() end
    end)

    it("schedules forced garbage collection only after repeated redraws", function()
        local scheduled = 0
        local UIManager = package.loaded["ui/uimanager"]
        UIManager.scheduleIn = function(_, delay, callback)
            scheduled = scheduled + 1
        end

        local menu = build_menu({
            dimen = make_dimen(),
            item_group = { clear = function() end },
            page_info = { resetLayout = function() end },
            page_info_text = { text = "", setText = function() end },
            return_button = { resetLayout = function() end },
            content_group = { resetLayout = function() end },
            show_parent = {},
            layout = {},
            items_to_update = {},
            _updateItemsBuildUI = function() return 1 end,
            _recalculateDimen = function() end,
            updatePageInfo = function() end,
        })

        for _ = 1, 4 do
            menu:updateItems(1, false)
        end
        assert.equal(0, scheduled)

        menu:updateItems(1, false)
        assert.equal(1, scheduled)
    end)

    it("schedules forced garbage collection when closing the menu", function()
        local scheduled_delay
        local UIManager = package.loaded["ui/uimanager"]
        UIManager.scheduleIn = function(_, delay, callback)
            scheduled_delay = delay
        end

        local menu = build_menu({
            item_group = { free = function() end },
            _covermenu_onclose_done = false,
        })

        menu:onCloseWidget()

        assert.equal(0.2, scheduled_delay)
    end)
end)

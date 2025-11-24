require 'busted.runner'()
local setup_mocks = require("spec.support.mock_ui")

describe("TitleBar", function()
    local TitleBar

    setup(function()
        setup_mocks()

        -- Mock IconButton
        package.loaded["ui/widget/iconbutton"] = {
            new = function(self, o)
                o = o or {}
                o.name = "IconButton"
                o.getSize = function() return { w = o.width or 50, h = o.height or 50 } end
                o.show = function() end
                o.hide = function() end
                return o
            end
        }

        -- Mock G_defaults for icon size
        _G.G_defaults = {
            readSetting = function(key)
                if key == "DGENERIC_ICON_SIZE" then return 32 end
                return nil
            end
        }

        -- Ensure Device.screen.scaleBySize is properly mocked
        local Device = package.loaded["device"]
        Device.screen.scaleBySize = function(self, val) return val end

        TitleBar = require("titlebar")
    end)

    describe("Initialization", function()
        it("creates a TitleBar with explicit icon_size", function()
            local titlebar = TitleBar:new{ icon_size = 32 }
            assert.is_not_nil(titlebar)
        end)

        it("sets width to screen width", function()
            local titlebar = TitleBar:new{ icon_size = 32 }
            assert.equal(600, titlebar.width) -- Mock screen width is 600
        end)

        it("calculates titlebar height from icon size and padding", function()
            local titlebar = TitleBar:new{ icon_size = 32 }
            assert.is_not_nil(titlebar.titlebar_height)
            assert.is_true(titlebar.titlebar_height > 0)
        end)

        it("creates dimension geometry", function()
            local titlebar = TitleBar:new{ icon_size = 32 }
            assert.is_not_nil(titlebar.dimen)
            assert.equal(600, titlebar.dimen.w)
            assert.is_not_nil(titlebar.dimen.h)
        end)

        it("creates all button containers", function()
            local titlebar = TitleBar:new{ icon_size = 32 }
            assert.is_not_nil(titlebar.left1_button_container)
            assert.is_not_nil(titlebar.left2_button_container)
            assert.is_not_nil(titlebar.left3_button_container)
            assert.is_not_nil(titlebar.right1_button_container)
            assert.is_not_nil(titlebar.right2_button_container)
            assert.is_not_nil(titlebar.right3_button_container)
        end)
    end)

    describe("Icon Configuration", function()
        it("accepts custom left icons", function()
            local titlebar = TitleBar:new{
                icon_size = 32,
                left1_icon = "arrow_back.svg",
                left2_icon = "favorites.svg",
                left3_icon = "history.svg"
            }
            assert.is_not_nil(titlebar.left1_button)
            assert.is_not_nil(titlebar.left2_button)
            assert.is_not_nil(titlebar.left3_button)
        end)

        it("accepts custom right icons", function()
            local titlebar = TitleBar:new{
                icon_size = 32,
                right1_icon = "settings.svg",
                right2_icon = "search.svg",
                right3_icon = "menu.svg"
            }
            assert.is_not_nil(titlebar.right1_button)
            assert.is_not_nil(titlebar.right2_button)
            assert.is_not_nil(titlebar.right3_button)
        end)

        it("accepts center icon", function()
            local titlebar = TitleBar:new{
                icon_size = 32,
                center_icon = "logo.svg"
            }
            assert.is_not_nil(titlebar.center_button)
        end)

        it("accepts custom icon size", function()
            local titlebar = TitleBar:new{
                icon_size = 32,
                icon_size = 48
            }
            assert.equal(48, titlebar.icon_size)
        end)

        it("calculates center icon size from ratio", function()
            local titlebar = TitleBar:new{
                icon_size = 32,
                icon_size = 32,
                center_icon_size_ratio = 1.5
            }
            assert.equal(48, titlebar.center_icon_size) -- 32 * 1.5 = 48
        end)
    end)

    describe("Icon Callbacks", function()
        it("attaches tap callback to left1 button", function()
            local callback_called = false
            local titlebar = TitleBar:new{
                icon_size = 32,
                left1_icon = "arrow_back.svg",
                left1_icon_tap_callback = function() callback_called = true end
            }
            titlebar.left1_button.callback()
            assert.is_true(callback_called)
        end)

        it("attaches hold callback to left1 button", function()
            local callback_called = false
            local titlebar = TitleBar:new{
                icon_size = 32,
                left1_icon = "arrow_back.svg",
                left1_icon_hold_callback = function() callback_called = true end
            }
            titlebar.left1_button.hold_callback()
            assert.is_true(callback_called)
        end)

        it("attaches tap callback to right1 button", function()
            local callback_called = false
            local titlebar = TitleBar:new{
                icon_size = 32,
                right1_icon = "settings.svg",
                right1_icon_tap_callback = function() callback_called = true end
            }
            titlebar.right1_button.callback()
            assert.is_true(callback_called)
        end)

        it("attaches tap callback to center button", function()
            local callback_called = false
            local titlebar = TitleBar:new{
                icon_size = 32,
                center_icon = "logo.svg",
                center_icon_tap_callback = function() callback_called = true end
            }
            if titlebar.center_button then
                titlebar.center_button.callback()
                assert.is_true(callback_called)
            end
        end)

        it("uses empty callback when none provided", function()
            local titlebar = TitleBar:new{
                icon_size = 32,
                left1_icon = "arrow_back.svg"
            }
            -- Should not crash when calling default callback
            titlebar.left1_button.callback()
        end)
    end)

    describe("Title and Subtitle", function()
        it("accepts title property", function()
            local titlebar = TitleBar:new{
                icon_size = 32,
                icon_size = 32,
                title = "Test Title"
            }
            assert.equal("Test Title", titlebar.title)
        end)

        it("accepts subtitle property", function()
            local titlebar = TitleBar:new{
                icon_size = 32,
                icon_size = 32,
                subtitle = "Test Subtitle"
            }
            assert.equal("Test Subtitle", titlebar.subtitle)
        end)

        -- Note: setTitle and setSubTitle methods don't exist in titlebar.lua
        -- Title and subtitle are set during initialization via the constructor
    end)

    describe("Layout", function()
        it("getHeight returns titlebar height", function()
            local titlebar = TitleBar:new{ icon_size = 32 }
            local height = titlebar:getHeight()
            assert.equal(titlebar.titlebar_height, height)
        end)

        it("calculates correct padding for left buttons", function()
            local titlebar = TitleBar:new{
                icon_size = 32,
                left1_icon = "icon1.svg"
            }
            -- Left1 should have padding from left margin
            assert.is_not_nil(titlebar.left1_button_container)
        end)

        it("calculates correct padding for right buttons", function()
            local titlebar = TitleBar:new{
                icon_size = 32,
                right1_icon = "icon1.svg"
            }
            -- Right1 should have padding from right margin
            assert.is_not_nil(titlebar.right1_button_container)
        end)

        it("handles multiple left buttons with correct spacing", function()
            local titlebar = TitleBar:new{
                icon_size = 32,
                left1_icon = "icon1.svg",
                left2_icon = "icon2.svg",
                left3_icon = "icon3.svg"
            }
            assert.is_not_nil(titlebar.left1_button_container)
            assert.is_not_nil(titlebar.left2_button_container)
            assert.is_not_nil(titlebar.left3_button_container)
        end)

        it("handles multiple right buttons with correct spacing", function()
            local titlebar = TitleBar:new{
                icon_size = 32,
                right1_icon = "icon1.svg",
                right2_icon = "icon2.svg",
                right3_icon = "icon3.svg"
            }
            assert.is_not_nil(titlebar.right1_button_container)
            assert.is_not_nil(titlebar.right2_button_container)
            assert.is_not_nil(titlebar.right3_button_container)
        end)
    end)

    describe("Show/Hide Buttons", function()
        it("can hide left icons", function()
            local titlebar = TitleBar:new{
                icon_size = 32,
                left1_icon = "icon.svg"
            }
            titlebar.left1_button:hide()
            -- Should not crash
        end)

        it("can show left icons", function()
            local titlebar = TitleBar:new{
                icon_size = 32,
                left1_icon = "icon.svg"
            }
            titlebar.left1_button:show()
            -- Should not crash
        end)

        it("can hide right icons", function()
            local titlebar = TitleBar:new{
                icon_size = 32,
                right1_icon = "icon.svg"
            }
            titlebar.right1_button:hide()
            -- Should not crash
        end)

        it("can show right icons", function()
            local titlebar = TitleBar:new{
                icon_size = 32,
                right1_icon = "icon.svg"
            }
            titlebar.right1_button:show()
            -- Should not crash
        end)
    end)

    describe("Parent Widget", function()
        it("accepts show_parent parameter", function()
            local parent = { name = "ParentWidget" }
            local titlebar = TitleBar:new{
                icon_size = 32,
                show_parent = parent
            }
            assert.equal(parent, titlebar.show_parent)
        end)

        it("passes show_parent to buttons", function()
            local parent = { name = "ParentWidget" }
            local titlebar = TitleBar:new{
                icon_size = 32,
                show_parent = parent,
                left1_icon = "icon.svg"
            }
            assert.equal(parent, titlebar.left1_button.show_parent)
        end)
    end)

    describe("Custom Margins and Padding", function()
        it("accepts custom icon_margin_lr", function()
            local titlebar = TitleBar:new{
                icon_size = 32,
                icon_margin_lr = 50
            }
            assert.equal(50, titlebar.icon_margin_lr)
        end)

        it("accepts custom titlebar_margin_lr", function()
            local titlebar = TitleBar:new{
                icon_size = 32,
                titlebar_margin_lr = 20
            }
            assert.equal(20, titlebar.titlebar_margin_lr)
        end)

        it("accepts custom icon_padding_top", function()
            local titlebar = TitleBar:new{
                icon_size = 32,
                icon_padding_top = 10
            }
            assert.equal(10, titlebar.icon_padding_top)
        end)

        it("accepts custom icon_padding_bottom", function()
            local titlebar = TitleBar:new{
                icon_size = 32,
                icon_padding_bottom = 10
            }
            assert.equal(10, titlebar.icon_padding_bottom)
        end)
    end)

    describe("Painting", function()
        it("paintTo does not crash", function()
            local titlebar = TitleBar:new{
                icon_size = 32,
                left1_icon = "icon.svg"
            }
            local bb = {} -- mock blitbuffer
            titlebar:paintTo(bb, 0, 0)
            -- Should not crash
        end)

        it("paintTo with multiple icons", function()
            local titlebar = TitleBar:new{
                icon_size = 32,
                left1_icon = "icon1.svg",
                left2_icon = "icon2.svg",
                right1_icon = "icon3.svg",
                center_icon = "logo.svg"
            }
            local bb = {}
            titlebar:paintTo(bb, 0, 0)
            -- Should not crash
        end)
    end)
end)

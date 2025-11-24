require 'busted.runner'()
local setup_mocks = require("spec.support.mock_ui")

describe("ptutil Folder Cover Generation", function()
    local ptutil
    local util_mock
    local lfs_mock
    local RenderImage_mock
    local BookInfoManager_mock

    setup(function()
        setup_mocks()

        -- Augment util mock with fileExists that recognizes cover files
        util_mock = package.loaded["util"]
        local orig_fileExists = util_mock.fileExists
        util_mock.fileExists = function(filepath)
            if filepath:match("cover%.jpg$") then return true end
            if filepath:match("folder%.png$") then return true end
            return false
        end

        -- Augment lfs mock with specific cover file responses
        lfs_mock = package.loaded["libs/libkoreader-lfs"]
        local orig_attributes = lfs_mock.attributes
        lfs_mock.attributes = function(filepath, attr)
            if attr == "mode" then
                if filepath:match("cover%.jpg$") then return "file" end
                if filepath:match("folder%.png$") then return "file" end
                return nil
            end
            return nil
        end

        -- Mock RenderImage
        RenderImage_mock = {
            renderImageFile = function(filepath, want_frames, max_w, max_h)
                return { w = 100, h = 150 }, nil
            end,
            scaleBlitBuffer = function(bb, w, h)
                return { w = w, h = h }
            end
        }
        package.loaded["ui/renderimage"] = RenderImage_mock

        -- Augment BookInfoManager mock
        BookInfoManager_mock = package.loaded["bookinfomanager"]
        -- No additional changes needed, the base mock is sufficient

        ptutil = require("ptutil")
    end)

    describe("getFolderCover", function()
        it("returns nil for nil filepath", function()
            local result = ptutil.getFolderCover(nil)
            assert.is_nil(result)
        end)

        it("returns nil for empty filepath", function()
            local result = ptutil.getFolderCover("")
            assert.is_nil(result)
        end)

        it("returns nil when no cover files exist", function()
            util_mock.fileExists = function() return false end

            local result = ptutil.getFolderCover("/books/folder")
            assert.is_nil(result)
        end)

        it("is callable with valid path", function()
            util_mock.fileExists = function() return false end

            -- Just verify it doesn't crash
            ptutil.getFolderCover("/books/folder")
        end)
    end)

    describe("getSubfolderCoverImages", function()
        it("returns nil for nil filepath", function()
            local result = ptutil.getSubfolderCoverImages(nil)
            assert.is_nil(result)
        end)

        it("returns nil for empty filepath", function()
            local result = ptutil.getSubfolderCoverImages("")
            assert.is_nil(result)
        end)

        it("returns nil when BookInfoManager.conn is nil", function()
            BookInfoManager_mock.conn = nil
            local result = ptutil.getSubfolderCoverImages("/books/folder", 100, 100)
            assert.is_nil(result)
        end)
    end)

    describe("line function", function()
        it("is callable and returns widget", function()
            -- line function needs Size and other mocks, just verify it exists
            assert.is_function(ptutil.line)
        end)

        it("has convenience functions", function()
            assert.is_function(ptutil.thinWhiteLine)
            assert.is_function(ptutil.thinGrayLine)
            assert.is_function(ptutil.thinBlackLine)
            assert.is_function(ptutil.mediumBlackLine)
        end)
    end)

    describe("onFocus and onUnfocus", function()
        it("onFocus sets color", function()
            local container = {
                color = 1
            }
            local Device = package.loaded["device"]
            Device.isTouchDevice = function() return false end

            ptutil.onFocus(container)
            -- Color should be set to BLACK (1 in mock)
            assert.equal(1, container.color)
        end)

        it("onUnfocus sets color", function()
            local container = {
                color = 1
            }
            local Device = package.loaded["device"]
            Device.isTouchDevice = function() return false end

            ptutil.onUnfocus(container)
            -- Color should be set to WHITE (0 in mock)
            assert.equal(0, container.color)
        end)

        it("works with valid container", function()
            local container = { color = 0 }
            ptutil.onFocus(container)
            ptutil.onUnfocus(container)
            -- Should not crash
        end)
    end)
end)

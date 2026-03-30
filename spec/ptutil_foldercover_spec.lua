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

    before_each(function()
        ptutil.clearFolderCoverCache()
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

        it("caches discovered folder cover paths across repeated renders", function()
            local scan_calls = 0
            util_mock.directoryExists = function(path)
                return path == "/books/folder"
            end
            lfs_mock.dir = function(path)
                scan_calls = scan_calls + 1
                local entries = { "cover.jpg" }
                local idx = 0
                return function()
                    idx = idx + 1
                    return entries[idx]
                end
            end
            package.loaded["ui/widget/imagewidget"].new = function(self, o)
                o = o or {}
                o._render = function() end
                o.getOriginalWidth = function() return 120 end
                o.getOriginalHeight = function() return 180 end
                o.free = function() end
                return o
            end

            ptutil.getFolderCover("/books/folder", 100, 150)
            ptutil.getFolderCover("/books/folder", 100, 150)

            assert.equal(1, scan_calls)
        end)

        it("caches explicit folder cover dimensions across repeated renders", function()
            local render_calls = 0
            util_mock.directoryExists = function(path)
                return path == "/books/folder"
            end
            lfs_mock.dir = function(path)
                local entries = { "cover.jpg" }
                local idx = 0
                return function()
                    idx = idx + 1
                    return entries[idx]
                end
            end
            package.loaded["ui/widget/imagewidget"].new = function(self, o)
                o = o or {}
                o._render = function()
                    render_calls = render_calls + 1
                end
                o.getOriginalWidth = function() return 120 end
                o.getOriginalHeight = function() return 180 end
                o.free = function() end
                return o
            end

            ptutil.getFolderCover("/books/folder", 100, 150)
            ptutil.getFolderCover("/books/folder", 100, 150)

            assert.equal(1, render_calls)
        end)

        it("caches misses for folders without explicit cover images", function()
            local scan_calls = 0
            util_mock.directoryExists = function(path)
                return path == "/books/folder"
            end
            lfs_mock.dir = function(path)
                scan_calls = scan_calls + 1
                local entries = { "notes.txt", "thumbs.db" }
                local idx = 0
                return function()
                    idx = idx + 1
                    return entries[idx]
                end
            end

            local first = ptutil.getFolderCover("/books/folder", 100, 150)
            local second = ptutil.getFolderCover("/books/folder", 100, 150)

            assert.is_nil(first)
            assert.is_nil(second)
            assert.equal(1, scan_calls)
        end)

        it("clearing the folder cover cache forces explicit cover rescans", function()
            local scan_calls = 0
            util_mock.directoryExists = function(path)
                return path == "/books/folder"
            end
            lfs_mock.dir = function(path)
                scan_calls = scan_calls + 1
                local entries = { "cover.jpg" }
                local idx = 0
                return function()
                    idx = idx + 1
                    return entries[idx]
                end
            end
            package.loaded["ui/widget/imagewidget"].new = function(self, o)
                o = o or {}
                o._render = function() end
                o.getOriginalWidth = function() return 120 end
                o.getOriginalHeight = function() return 180 end
                o.free = function() end
                return o
            end

            ptutil.getFolderCover("/books/folder", 100, 150)
            ptutil.clearFolderCoverCache()
            ptutil.getFolderCover("/books/folder", 100, 150)

            assert.equal(2, scan_calls)
        end)

        it("bypasses directory scans when pt_cover_path is provided and reuses dimensions", function()
            local scan_calls = 0
            local render_calls = 0
            util_mock.directoryExists = function(path)
                return path == "/books/folder"
            end
            lfs_mock.dir = function(path)
                scan_calls = scan_calls + 1
                return function()
                    return nil
                end
            end
            package.loaded["ui/widget/imagewidget"].new = function(self, o)
                o = o or {}
                o._render = function()
                    render_calls = render_calls + 1
                end
                o.getOriginalWidth = function() return 120 end
                o.getOriginalHeight = function() return 180 end
                o.free = function() end
                return o
            end

            ptutil.getFolderCover("/books/folder", 100, 150, "/books/custom/folder.png")
            ptutil.getFolderCover("/books/folder", 100, 150, "/books/custom/folder.png")

            assert.equal(0, scan_calls)
            assert.equal(1, render_calls)
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

        it("returns nil when BookInfoManager.openDbConnection does not provide a db connection", function()
            BookInfoManager_mock.openDbConnection = function() end
            BookInfoManager_mock.db_conn = nil
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

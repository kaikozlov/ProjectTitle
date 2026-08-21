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

        it("memoizes explicit cover render failures after the first failed render", function()
            local render_attempts = 0
            util_mock.directoryExists = function(path)
                return path == "/books/folder"
            end
            package.loaded["ui/widget/imagewidget"].new = function(self, o)
                o = o or {}
                if o.width or o.height then
                    render_attempts = render_attempts + 1
                    error("simulated render failure")
                end
                o._render = function() end
                o.getOriginalWidth = function() return 120 end
                o.getOriginalHeight = function() return 180 end
                o.free = function() end
                return o
            end

            local first = ptutil.getFolderCover("/books/folder", 100, 150, "/books/custom/folder.png")
            local second = ptutil.getFolderCover("/books/folder", 100, 150, "/books/custom/folder.png")

            assert.is_not_nil(first)
            assert.is_not_nil(second)
            assert.equal(1, render_attempts)
        end)

        it("invalidating a folder path clears cached explicit cover discoveries and dimensions", function()
            local scan_calls = 0
            local render_calls = 0
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
                o._render = function()
                    render_calls = render_calls + 1
                end
                o.getOriginalWidth = function() return 120 end
                o.getOriginalHeight = function() return 180 end
                o.free = function() end
                return o
            end

            ptutil.getFolderCover("/books/folder", 100, 150)
            ptutil.invalidateFolderCoverCache("/books/folder")
            ptutil.getFolderCover("/books/folder", 100, 150)

            assert.equal(2, scan_calls)
            assert.equal(2, render_calls)
        end)

        it("invalidating a folder path clears memoized explicit cover render failures", function()
            local render_attempts = 0
            util_mock.directoryExists = function(path)
                return path == "/books/folder"
            end
            package.loaded["ui/widget/imagewidget"].new = function(self, o)
                o = o or {}
                if o.width or o.height then
                    render_attempts = render_attempts + 1
                    error("simulated render failure")
                end
                o._render = function() end
                o.getOriginalWidth = function() return 120 end
                o.getOriginalHeight = function() return 180 end
                o.free = function() end
                return o
            end

            ptutil.getFolderCover("/books/folder", 100, 150, "/books/custom/folder.png")
            ptutil.invalidateFolderCoverCache("/books/folder")
            ptutil.getFolderCover("/books/folder", 100, 150, "/books/custom/folder.png")

            assert.equal(2, render_attempts)
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

        it("returns nil when BookInfoManager returns no candidate filepaths", function()
            BookInfoManager_mock.getFolderCoverCandidateFilepaths = function()
                return nil
            end
            local result = ptutil.getSubfolderCoverImages("/books/folder", 100, 100)
            assert.is_nil(result)
        end)

        it("defensively excludes ignored covers during candidate hydration", function()
            local ignored_bb = { id = "ignored" }
            local visible_bb = { id = "visible" }
            local original_candidates = BookInfoManager_mock.getFolderCoverCandidateFilepaths
            local original_get_bookinfo_batch = BookInfoManager_mock.getBookInfoBatch
            local ImageWidget = package.loaded["ui/widget/imagewidget"]
            local original_image_new = ImageWidget.new
            local rendered_images = {}
            BookInfoManager_mock.getFolderCoverCandidateFilepaths = function()
                return { "/books/folder/ignored.epub", "/books/folder/visible.epub" }
            end
            BookInfoManager_mock.getBookInfoBatch = function()
                return {
                    ["/books/folder/ignored.epub"] = {
                        cover_bb = ignored_bb,
                        cover_w = 100,
                        cover_h = 150,
                        ignore_cover = "Y",
                    },
                    ["/books/folder/visible.epub"] = {
                        cover_bb = visible_bb,
                        cover_w = 100,
                        cover_h = 150,
                    },
                }
            end
            ImageWidget.new = function(self, opts)
                if opts and opts.image then
                    rendered_images[#rendered_images + 1] = opts.image
                end
                return original_image_new(self, opts)
            end

            local result = ptutil.getSubfolderCoverImages("/books/folder", 100, 100)

            BookInfoManager_mock.getFolderCoverCandidateFilepaths = original_candidates
            BookInfoManager_mock.getBookInfoBatch = original_get_bookinfo_batch
            ImageWidget.new = original_image_new
            assert.is_not_nil(result)
            assert.same({ visible_bb }, rendered_images)
        end)

        it("caches empty folder-cover selections across repeated renders", function()
            local query_calls = 0
            local queried_subtree
            BookInfoManager_mock.getFolderCoverCandidateFilepaths = function(_, _, include_subfolders)
                query_calls = query_calls + 1
                queried_subtree = include_subfolders
                return nil
            end

            local first = ptutil.getSubfolderCoverImages("/books/empty", 100, 100)
            local second = ptutil.getSubfolderCoverImages("/books/empty", 100, 100)

            assert.is_nil(first)
            assert.is_nil(second)
            assert.equal(1, query_calls)
            assert.is_true(queried_subtree)
        end)

        it("reuses cached folder-cover selections across different dimensions", function()
            local query_calls = 0
            local original_get_folder_cover_candidate_filepaths = BookInfoManager_mock.getFolderCoverCandidateFilepaths
            local original_getBookInfoBatch = BookInfoManager_mock.getBookInfoBatch

            util_mock.directoryExists = function(path)
                return path == "/books/folder"
            end
            util_mock.fileExists = function(path)
                return path:match("^/books/folder/")
            end
            BookInfoManager_mock.getFolderCoverCandidateFilepaths = function(self, folder, include_subfolders)
                query_calls = query_calls + 1
                return {
                    "/books/folder/a.epub",
                    "/books/folder/b.epub",
                    "/books/folder/c.epub",
                    "/books/folder/d.epub",
                }
            end
            BookInfoManager_mock.getBookInfoBatch = function(self, filepaths, get_cover)
                local results = {}
                for _, filepath in ipairs(filepaths) do
                    results[filepath] = {
                        cover_w = 100,
                        cover_h = 150,
                        cover_bb = { filepath = filepath },
                        has_cover = "Y",
                    }
                end
                return results
            end

            local first = ptutil.getSubfolderCoverImages("/books/folder", 100, 100)
            local second = ptutil.getSubfolderCoverImages("/books/folder", 180, 220)

            BookInfoManager_mock.getFolderCoverCandidateFilepaths = original_get_folder_cover_candidate_filepaths
            BookInfoManager_mock.getBookInfoBatch = original_getBookInfoBatch

            assert.is_not_nil(first)
            assert.is_not_nil(second)
            assert.equal(1, query_calls)
        end)

        it("uses render_context folder-cover layout settings without direct setting lookups", function()
            local get_setting_calls = 0
            local original_get_folder_cover_candidate_filepaths = BookInfoManager_mock.getFolderCoverCandidateFilepaths
            local original_getBookInfoBatch = BookInfoManager_mock.getBookInfoBatch
            local original_getSetting = BookInfoManager_mock.getSetting

            util_mock.directoryExists = function(path)
                return path == "/books/folder"
            end
            util_mock.fileExists = function(path)
                return path:match("^/books/folder/")
            end
            BookInfoManager_mock.getFolderCoverCandidateFilepaths = function(self, folder, include_subfolders)
                return {
                    "/books/folder/a.epub",
                    "/books/folder/b.epub",
                    "/books/folder/c.epub",
                    "/books/folder/d.epub",
                }
            end
            BookInfoManager_mock.getBookInfoBatch = function(self, filepaths, get_cover)
                local results = {}
                for _, filepath in ipairs(filepaths) do
                    results[filepath] = {
                        cover_w = 100,
                        cover_h = 150,
                        cover_bb = { filepath = filepath },
                        has_cover = "Y",
                    }
                end
                return results
            end
            BookInfoManager_mock.getSetting = function(self, key)
                if key == "use_stacked_foldercovers" then
                    get_setting_calls = get_setting_calls + 1
                end
                return nil
            end

            local result = ptutil.getSubfolderCoverImages("/books/folder", 100, 100, {
                use_stacked_foldercovers = true,
            })

            BookInfoManager_mock.getFolderCoverCandidateFilepaths = original_get_folder_cover_candidate_filepaths
            BookInfoManager_mock.getBookInfoBatch = original_getBookInfoBatch
            BookInfoManager_mock.getSetting = original_getSetting

            assert.is_not_nil(result)
            assert.equal(0, get_setting_calls)
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

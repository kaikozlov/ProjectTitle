require 'busted.runner'()
local setup_mocks = require("spec.support.mock_ui")

describe("ptutil Formatting Functions", function()
    local ptutil

    setup(function()
        setup_mocks()
        ptutil = require("ptutil")
    end)

    describe("formatAuthors", function()
        it("returns empty string for nil authors", function()
            local result = ptutil.formatAuthors(nil)
            assert.equal("", result)
        end)

        it("returns empty string for empty string", function()
            local result = ptutil.formatAuthors("")
            assert.equal("", result)
        end)

        it("formats single author", function()
            local result = ptutil.formatAuthors("John Doe")
            assert.equal("John Doe", result)
        end)

        it("formats multiple authors with newline separator", function()
            local result = ptutil.formatAuthors("John Doe\nJane Smith")
            -- Should have newline preserved or processed by BD.auto
            assert.is_not_nil(result)
            assert.is_string(result)
        end)

        it("formats authors with limit and et al.", function()
            local result = ptutil.formatAuthors("John Doe\nJane Smith\nBob Johnson", 2)
            -- Should include "et al." for 2nd author when limit is 2 and there are more
            assert.match("et al%.", result)
        end)

        it("respects authors_limit parameter", function()
            local result = ptutil.formatAuthors("A\nB\nC\nD\nE", 1)
            assert.match("et al%.", result)
        end)

        it("handles authors without newlines", function()
            local result = ptutil.formatAuthors("O'Brien, John")
            assert.is_not_nil(result)
            assert.is_string(result)
        end)
    end)

    describe("formatSeries", function()
        it("returns empty string for empty series", function()
            local result = ptutil.formatSeries("")
            assert.equal("", result)
        end)

        it("formats series without index", function()
            local result = ptutil.formatSeries("The Great Series")
            assert.equal("The Great Series", result)
        end)

        it("formats series with integer index", function()
            local result = ptutil.formatSeries("The Great Series", 1)
            -- Format is "#index - series"
            assert.match("#1", result)
            assert.match("The Great Series", result)
        end)

        it("formats series with zero index returns empty", function()
            local result = ptutil.formatSeries("Prequel Series", 0)
            assert.equal("", result)
        end)

        it("handles series with colon subseries extraction", function()
            local result = ptutil.formatSeries("Big Series: Small Subseries", 1)
            -- Should extract "Small Subseries" after the colon
            assert.match("Small Subseries", result)
            assert.not_match("Big Series:", result)
        end)
    end)

    describe("formatAuthorSeries", function()
        it("returns empty string when both authors and series are nil/empty", function()
            local result = ptutil.formatAuthorSeries(nil, nil)
            assert.equal("", result)
        end)

        it("returns only authors when series is empty", function()
            local result = ptutil.formatAuthorSeries("John Doe", "", "series_in_separate_line")
            assert.equal("John Doe", result)
        end)

        it("returns only series when authors is nil in series_in_separate_line mode", function()
            local result = ptutil.formatAuthorSeries(nil, "Great Series #1", "series_in_separate_line")
            assert.equal("Great Series #1", result)
        end)

        it("formats with series_in_separate_line mode with newline", function()
            local result = ptutil.formatAuthorSeries("John Doe", "Great Series #1", "series_in_separate_line")
            -- Should contain both with newline separator
            assert.match("John Doe", result)
            assert.match("Great Series #1", result)
        end)

        it("can place series before authors when configured", function()
            local result = ptutil.formatAuthorSeries("John Doe", "Great Series #1", "series_in_separate_line", false, "series_first")
            assert.equal("Great Series #1\nJohn Doe", result)
        end)

        it("can place series before authors when tags are shown", function()
            local result = ptutil.formatAuthorSeries("John Doe\nJane Smith", "Great Series #1", "series_in_separate_line", true, "series_first")
            assert.equal("Great Series #1" .. ptutil.separator.dot .. "John Doe, Jane Smith", result)
        end)

        it("handles empty authors string", function()
            local result = ptutil.formatAuthorSeries("", "Great Series #1", "series_in_separate_line")
            assert.equal("Great Series #1", result)
        end)

        it("handles empty series string", function()
            local result = ptutil.formatAuthorSeries("John Doe", "", "series_in_separate_line")
            assert.equal("John Doe", result)
        end)
    end)

    describe("formatTags", function()
        it("returns nil for nil keywords", function()
            assert.is_nil(ptutil.formatTags(nil))
        end)

        it("returns nil for empty string", function()
            assert.is_nil(ptutil.formatTags(""))
        end)

        it("formats single tag", function()
            local result = ptutil.formatTags("fiction")
            assert.is_not_nil(result)
            assert.match("fiction", result)
        end)

        it("formats multiple tags with newline separator", function()
            local result = ptutil.formatTags("fiction\nscience\nadventure")
            assert.is_not_nil(result)
            assert.is_string(result)
        end)

        it("formats semicolon-separated tags when newlines are absent", function()
            local result = ptutil.formatTags("fiction; science ;adventure")
            assert.equal("fiction" .. ptutil.separator.bullet .. "science" .. ptutil.separator.bullet .. "adventure", result)
        end)

        it("formats comma-separated tags when newlines and semicolons are absent", function()
            local result = ptutil.formatTags("fiction, science ,adventure")
            assert.equal("fiction" .. ptutil.separator.bullet .. "science" .. ptutil.separator.bullet .. "adventure", result)
        end)

        it("prefers newline separators over commas in mixed input", function()
            local result = ptutil.formatTags("fiction, science\nadventure")
            assert.equal("fiction, science" .. ptutil.separator.bullet .. "adventure", result)
        end)

        it("formats tags with limit", function()
            local result = ptutil.formatTags("fiction\nscience\nadventure\nmystery\nthriller", 3)
            assert.is_not_nil(result)
            -- Should limit to 3 tags
            local count = select(2, result:gsub(",", ","))
            assert.is_true(count <= 3)
        end)
    end)

    describe("showProgressBar", function()
        it("returns page count and show flag", function()
            local BookInfoManager = require("bookinfomanager")
            BookInfoManager._settings = {}

            local width, show = ptutil.showProgressBar(100)
            assert.is_not_nil(width)
            -- show can be nil, false, or true depending on settings
            -- Just verify function returns without error
        end)

        it("returns page count parameter when provided", function()
            local BookInfoManager = require("bookinfomanager")
            BookInfoManager._settings = {}

            local width, show = ptutil.showProgressBar(250)
            assert.equal(250, width)
        end)

        it("show flag depends on settings", function()
            local BookInfoManager = require("bookinfomanager")
            BookInfoManager._settings = {
                hide_file_info = "Y"
            }

            local width, show = ptutil.showProgressBar(100)
            -- Show depends on multiple settings, can be nil/false/true
            -- Just verify function returns without error
        end)
    end)

    describe("isPathChooser", function()
        it("returns false when no title_bar or menu", function()
            assert.is_false(ptutil.isPathChooser({}))
        end)

        it("returns true when title_bar has non-empty title", function()
            local obj = { title_bar = { title = "Select a folder" } }
            assert.is_true(ptutil.isPathChooser(obj))
        end)

        it("returns false when title_bar has empty title", function()
            local obj = { title_bar = { title = "" } }
            assert.is_false(ptutil.isPathChooser(obj))
        end)

        it("returns true when menu has non-empty title", function()
            local obj = { menu = { title = "Choose path" } }
            assert.is_true(ptutil.isPathChooser(obj))
        end)

        it("returns false when menu has empty title", function()
            local obj = { menu = { title = "" } }
            assert.is_false(ptutil.isPathChooser(obj))
        end)
    end)

    describe("formatFooterText", function()
        local BookInfoManager
        local original_read_setting
        local original_nil_or_true
        local original_is_true
        local Device
        local original_network_manager
        local original_datetime
        local original_bd_wrap

        setup(function()
            BookInfoManager = require("bookinfomanager")
            original_read_setting = G_reader_settings.readSetting
            original_nil_or_true = G_reader_settings.nilOrTrue
            original_is_true = G_reader_settings.isTrue
            Device = package.loaded["device"]
            original_network_manager = package.loaded["ui/network/manager"]
            original_datetime = package.loaded["datetime"]
            original_bd_wrap = package.loaded["ui/bidi"].wrap
        end)

        teardown(function()
            G_reader_settings.readSetting = original_read_setting
            G_reader_settings.nilOrTrue = original_nil_or_true
            G_reader_settings.isTrue = original_is_true
            package.loaded["ui/network/manager"] = original_network_manager
            package.loaded["datetime"] = original_datetime
            package.loaded["ui/bidi"].wrap = original_bd_wrap
        end)

        it("shows Home for the configured home directory", function()
            BookInfoManager:saveSetting("replace_footer_text", false)
            G_reader_settings.readSetting = function(_, key)
                if key == "home_dir" then
                    return "/mnt/us/books"
                end
                return nil
            end
            G_reader_settings.nilOrTrue = function(_, key)
                return key == "shorten_home_dir"
            end

            local result = ptutil.formatFooterText(nil, nil, "/mnt/us/books", "/mnt/us", false, false)

            assert.equal("Home", result)
        end)

        it("does not show Home for the default directory when a custom home is configured", function()
            BookInfoManager:saveSetting("replace_footer_text", false)
            G_reader_settings.readSetting = function(_, key)
                if key == "home_dir" then
                    return "/mnt/us/books"
                end
                return nil
            end
            G_reader_settings.nilOrTrue = function(_, key)
                return key == "shorten_home_dir"
            end

            local result = ptutil.formatFooterText(nil, nil, "/mnt/us", "/mnt/us", false, false)

            assert.equal("us", result)
        end)

        it("falls back to the default directory as Home when no custom home is configured", function()
            BookInfoManager:saveSetting("replace_footer_text", false)
            G_reader_settings.readSetting = function()
                return nil
            end
            G_reader_settings.nilOrTrue = function(_, key)
                return key == "shorten_home_dir"
            end

            local result = ptutil.formatFooterText(nil, nil, "/mnt/us", "/mnt/us", false, false)

            assert.equal("Home", result)
        end)

        it("shows only enabled device info items", function()
            BookInfoManager:saveSetting("config_version", "11")
            BookInfoManager:saveSetting("replace_footer_text", true)
            BookInfoManager:saveSetting("footer_show_clock", false)
            BookInfoManager:saveSetting("footer_show_wifi", false)
            BookInfoManager:saveSetting("footer_show_battery", true)
            BookInfoManager:saveSetting("footer_show_frontlight", false)
            BookInfoManager:saveSetting("footer_show_frontlight_warmth", false)

            package.loaded["ui/bidi"].wrap = function(text) return text end
            package.loaded["datetime"] = {
                secondsToHour = function() return "10:30" end,
            }
            G_reader_settings.isTrue = function() return false end
            package.loaded["ui/network/manager"] = {
                isWifiOn = function() return false end,
            }
            Device.hasBattery = function() return true end
            Device.hasAuxBattery = function() return false end
            Device.hasFrontlight = function() return false end
            Device.hasNaturalLight = function() return false end
            Device.getPowerDevice = function()
                return {
                    getCapacity = function() return 50 end,
                    getBatterySymbol = function() return "B" end,
                    isCharged = function() return false end,
                    isCharging = function() return false end,
                }
            end

            local result = ptutil.formatFooterText(nil, nil, "/mnt/us", "/mnt/us", false, false)

            assert.equal("B50%", result)
        end)

        it("preserves the fixed item order while omitting disabled items", function()
            BookInfoManager:saveSetting("config_version", "11")
            BookInfoManager:saveSetting("replace_footer_text", true)
            BookInfoManager:saveSetting("footer_show_clock", true)
            BookInfoManager:saveSetting("footer_show_wifi", false)
            BookInfoManager:saveSetting("footer_show_battery", true)
            BookInfoManager:saveSetting("footer_show_frontlight", false)
            BookInfoManager:saveSetting("footer_show_frontlight_warmth", false)

            package.loaded["ui/bidi"].wrap = function(text) return text end
            package.loaded["datetime"] = {
                secondsToHour = function() return "10:30" end,
            }
            G_reader_settings.isTrue = function() return false end
            package.loaded["ui/network/manager"] = {
                isWifiOn = function() return false end,
            }
            Device.hasBattery = function() return true end
            Device.hasAuxBattery = function() return false end
            Device.hasFrontlight = function() return false end
            Device.hasNaturalLight = function() return false end
            Device.getPowerDevice = function()
                return {
                    getCapacity = function() return 50 end,
                    getBatterySymbol = function() return "B" end,
                    isCharged = function() return false end,
                    isCharging = function() return false end,
                }
            end

            local result = ptutil.formatFooterText(nil, nil, "/mnt/us", "/mnt/us", false, false)

            assert.equal("10:30" .. ptutil.separator.dot .. "B50%", result)
        end)
    end)

    describe("getFontFace", function()
        it("falls back cleanly when direct font lookup errors", function()
            local ui_font = package.loaded["ui/font"]
            local original_get_face = ui_font.getFace
            ui_font.getFace = function(_, font_name, size)
                if font_name == ptutil.good_sans or font_name == ptutil.good_serif then
                    error("font lookup failed")
                end
                if font_name == "cfont" then
                    return { name = font_name, size = size }
                end
                return nil
            end

            ptutil.resetFontCheck()
            local ok, face = pcall(ptutil.getFontFace, ptutil.good_serif, 18)

            ui_font.getFace = original_get_face
            ptutil.resetFontCheck()

            assert.is_true(ok)
            assert.equal("cfont", face.name)
        end)

        it("reuses the last known good core font when later lookups fail", function()
            local ui_font = package.loaded["ui/font"]
            local original_get_face = ui_font.getFace
            ui_font.getFace = function(_, font_name, size)
                if font_name == "cfont" then
                    return { name = font_name, size = size }
                end
                return nil
            end

            ptutil.resetFontCheck()
            local first_face = ptutil.getFontFace(ptutil.good_serif, 18)

            ui_font.getFace = function() return nil end
            local second_face = ptutil.getFontFace(ptutil.good_serif, 18)

            ui_font.getFace = original_get_face
            ptutil.resetFontCheck()

            assert.is_not_nil(first_face)
            assert.is_not_nil(second_face)
            assert.equal("cfont", second_face.name)
        end)

        it("reuses an already loaded KOReader face when all font lookups fail", function()
            local ui_font = package.loaded["ui/font"]
            local original_get_face = ui_font.getFace
            local original_faces = ui_font.faces
            local cached_face = { name = "cached-face", size = 16 }

            ui_font.faces = {
                cached = cached_face,
            }
            ui_font.getFace = function()
                return nil
            end

            ptutil.resetFontCheck()
            local face = ptutil.getFontFace(ptutil.good_serif, 18)

            ui_font.getFace = original_get_face
            ui_font.faces = original_faces
            ptutil.resetFontCheck()

            assert.equal(cached_face, face)
        end)
    end)
end)

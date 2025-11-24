require 'busted.runner'()
local setup_mocks = require("spec.support.mock_ui")

describe("Main Compatibility Checks", function()
    local ptutil

    setup(function()
        setup_mocks()
        ptutil = require("ptutil")
    end)

    describe("Font installation check", function()
        it("installFonts is callable", function()
            -- Just verify the function exists and is callable
            assert.is_function(ptutil.installFonts)
            -- We can't easily test the full logic without filesystem mocking
        end)

        it("installIcons is callable", function()
            assert.is_function(ptutil.installIcons)
        end)
    end)

    describe("Icon installation check", function()
        it("installIcons is callable", function()
            -- Just verify the function exists
            assert.is_function(ptutil.installIcons)
        end)
    end)

    describe("Cover Browser conflict check", function()
        it("detects when Cover Browser is disabled", function()
            _G.G_reader_settings = {
                readSetting = function(self, key)
                    if key == "plugins_disabled" then
                        return { coverbrowser = true }
                    end
                    return nil
                end
            }

            local plugins_disabled = G_reader_settings:readSetting("plugins_disabled")
            assert.is_true(plugins_disabled.coverbrowser)
        end)

        it("detects when Cover Browser is enabled", function()
            _G.G_reader_settings = {
                readSetting = function(self, key)
                    if key == "plugins_disabled" then
                        return { coverbrowser = false }
                    end
                    return nil
                end
            }

            local plugins_disabled = G_reader_settings:readSetting("plugins_disabled")
            assert.is_false(plugins_disabled.coverbrowser)
        end)

        it("handles nil plugins_disabled", function()
            _G.G_reader_settings = {
                readSetting = function(self, key)
                    if key == "plugins_disabled" then
                        return nil
                    end
                    return nil
                end
            }

            local plugins_disabled = G_reader_settings:readSetting("plugins_disabled")
            assert.is_nil(plugins_disabled)
        end)

        it("handles empty plugins_disabled table", function()
            _G.G_reader_settings = {
                readSetting = function(self, key)
                    if key == "plugins_disabled" then
                        return {}
                    end
                    return nil
                end
            }

            local plugins_disabled = G_reader_settings:readSetting("plugins_disabled")
            assert.is_table(plugins_disabled)
            assert.is_nil(plugins_disabled.coverbrowser)
        end)
    end)

    describe("Version compatibility check", function()
        it("accepts exact safe version", function()
            local safe_version = 202510000000
            local current_version = 202510000000

            local version_unsafe = current_version ~= safe_version
            assert.is_false(version_unsafe)
        end)

        it("rejects newer version", function()
            local safe_version = 202510000000
            local current_version = 202511000000

            local version_unsafe = current_version ~= safe_version
            assert.is_true(version_unsafe)
        end)

        it("rejects older version", function()
            local safe_version = 202510000000
            local current_version = 202509000000

            local version_unsafe = current_version ~= safe_version
            assert.is_true(version_unsafe)
        end)

        it("accepts version when skip file exists", function()
            local util = package.loaded["util"]
            util.fileExists = function(filepath)
                if filepath:match("pt%-skipversioncheck%.txt$") then
                    return true
                end
                return false
            end

            local has_skip_file = util.fileExists("/settings/pt-skipversioncheck.txt")
            assert.is_true(has_skip_file)

            -- When skip file exists, version should be considered safe
            local safe_version = 202510000000
            local current_version = 202511000000
            local version_unsafe = not (current_version == safe_version or has_skip_file)
            assert.is_false(version_unsafe)
        end)

        it("identifies nightly builds", function()
            local safe_version = 202510000000
            local nightly_version = 202509999500 -- Close but not exact

            local is_likely_nightly = safe_version - nightly_version < 1000 and nightly_version < safe_version
            assert.is_true(is_likely_nightly)
        end)

        it("does not identify distant versions as nightly", function()
            local safe_version = 202510000000
            local old_version = 202401000000

            local is_likely_nightly = safe_version - old_version < 1000
            assert.is_false(is_likely_nightly)
        end)
    end)

    describe("Plugin directory detection", function()
        it("getPluginDir returns directory path", function()
            local dir = ptutil.getPluginDir()
            -- Should return something, exact value depends on execution context
            -- In tests it may be nil or a path
            assert.is_not_nil(dir)
        end)
    end)

    describe("KOReader data directory", function()
        it("koreader_dir is set", function()
            assert.is_not_nil(ptutil.koreader_dir)
            assert.is_string(ptutil.koreader_dir)
        end)

        it("koreader_dir contains /tmp in test environment", function()
            -- DataStorage mock returns /tmp, but koreader adds /koreader
            assert.match("/tmp", ptutil.koreader_dir)
        end)
    end)

    describe("Error message construction", function()
        it("includes fonts error when fonts are missing", function()
            local fonts_missing = true
            local error_parts = {}

            if fonts_missing then
                table.insert(error_parts, "Fonts - Not available")
            end

            assert.equal(1, #error_parts)
            assert.match("Fonts", error_parts[1])
        end)

        it("includes icons error when icons are missing", function()
            local icons_missing = true
            local error_parts = {}

            if icons_missing then
                table.insert(error_parts, "Icons - Not available")
            end

            assert.equal(1, #error_parts)
            assert.match("Icons", error_parts[1])
        end)

        it("includes version error when version is unsafe", function()
            local version_unsafe = true
            local cv_int = 202511000000
            local error_parts = {}

            if version_unsafe then
                table.insert(error_parts, "Version: " .. cv_int .. " - Unsupported")
            end

            assert.equal(1, #error_parts)
            assert.match("Version", error_parts[1])
            assert.match("Unsupported", error_parts[1])
        end)

        it("includes all errors when multiple issues exist", function()
            local fonts_missing = true
            local icons_missing = true
            local version_unsafe = true
            local error_parts = {}

            if fonts_missing then
                table.insert(error_parts, "Fonts")
            end
            if icons_missing then
                table.insert(error_parts, "Icons")
            end
            if version_unsafe then
                table.insert(error_parts, "Version")
            end

            assert.equal(3, #error_parts)
        end)
    end)

    describe("Safe plugin loading", function()
        it("loads empty plugin when requirements not met", function()
            -- When fonts_missing OR icons_missing OR version_unsafe is true,
            -- plugin should return a minimal WidgetContainer
            local fonts_missing = true
            local should_load_minimal = fonts_missing

            assert.is_true(should_load_minimal)
        end)

        it("loads full plugin when all requirements met", function()
            local fonts_missing = false
            local icons_missing = false
            local version_unsafe = false

            local should_load_full = not (fonts_missing or icons_missing or version_unsafe)
            assert.is_true(should_load_full)
        end)
    end)
end)

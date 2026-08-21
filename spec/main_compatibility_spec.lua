require("busted.runner")()

local main_loader = require("spec.support.main_loader")

describe("Main Compatibility Checks", function()
    it("returns a disabled plugin when upstream Cover Browser is still enabled", function()
        local main = main_loader.load_main({
            plugins_disabled = { coverbrowser = false },
        })

        assert.is_true(main.disabled)
    end)

    it("shows a load error when fonts are unavailable", function()
        local main, state = main_loader.load_main({
            fonts_available = false,
        })

        assert.equal("projecttitlenil", main.name)
        assert.equal(1, #state.shown_messages)
        assert.match("Fonts", state.shown_messages[1].text)
        assert.match("Not available", state.shown_messages[1].text)
    end)

    it("shows a load error when icons are unavailable", function()
        local main, state = main_loader.load_main({
            icons_available = false,
        })

        assert.equal("projecttitlenil", main.name)
        assert.equal(1, #state.shown_messages)
        assert.match("Icons", state.shown_messages[1].text)
        assert.match("Not available", state.shown_messages[1].text)
    end)

    it("shows a version error for significantly older unsupported builds", function()
        local main, state = main_loader.load_main({
            current_version = main_loader.SAFE_VERSION - 1000000,
        })

        assert.equal("projecttitlenil", main.name)
        assert.equal(1, #state.shown_messages)
        assert.match("Unsupported", state.shown_messages[1].text)
        assert.match(tostring(main_loader.SAFE_VERSION - 1000000), state.shown_messages[1].text)
    end)

    it("combines all startup failures into a single user-visible message", function()
        local main, state = main_loader.load_main({
            fonts_available = false,
            icons_available = false,
            current_version = main_loader.SAFE_VERSION - 1000000,
        })

        assert.equal("projecttitlenil", main.name)
        assert.equal(1, #state.shown_messages)
        assert.match("Fonts", state.shown_messages[1].text)
        assert.match("Icons", state.shown_messages[1].text)
        assert.match("Unsupported", state.shown_messages[1].text)
    end)

    it("loads the full plugin on the exact safe version", function()
        local main, state = main_loader.load_main({
            current_version = main_loader.SAFE_VERSION,
        })

        assert.equal("projecttitle", main.name)
        assert.equal(0, #state.shown_messages)
        assert.is_function(main._runSettingsMigrations)
    end)

    it("rejects newer builds that are not explicitly listed", function()
        local main, state = main_loader.load_main({
            current_version = main_loader.SAFE_VERSION + 1000000,
        })

        assert.equal("projecttitlenil", main.name)
        assert.equal(1, #state.shown_messages)
        assert.match("Unsupported", state.shown_messages[1].text)
    end)

    it("rejects slightly older builds that are not explicitly listed", function()
        local main, state = main_loader.load_main({
            current_version = main_loader.SAFE_VERSION - 100,
        })

        assert.equal("projecttitlenil", main.name)
        assert.equal(1, #state.shown_messages)
        assert.match("Unsupported", state.shown_messages[1].text)
    end)

    it("loads the full plugin when the skip-version file is present", function()
        local main, state = main_loader.load_main({
            current_version = main_loader.SAFE_VERSION - 1000000,
            skip_version_file = true,
        })

        assert.equal("projecttitle", main.name)
        assert.equal(0, #state.shown_messages)
    end)
end)

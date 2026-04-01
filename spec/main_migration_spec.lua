require("busted.runner")()

local main_loader = require("spec.support.main_loader")

describe("Main Settings Migration", function()
    it("migrates a fresh install all the way to version 12", function()
        local main, state, BookInfoManager = main_loader.load_main({
            initial_setup_done = false,
        })

        local restart_needed = main._runSettingsMigrations()

        assert.is_true(restart_needed)
        assert.equal(12, BookInfoManager:getSetting("config_version"))
        assert.equal("list_image_meta", BookInfoManager:getSetting("filemanager_display_mode"))
        assert.equal("list_image_meta", BookInfoManager:getSetting("history_display_mode"))
        assert.equal("list_image_meta", BookInfoManager:getSetting("collection_display_mode"))
        assert.equal("series_in_separate_line", BookInfoManager:getSetting("series_mode"))
        assert.equal("Y", BookInfoManager:getSetting("hide_file_info"))
        assert.equal("Y", BookInfoManager:getSetting("show_mosaic_titles"))
        assert.equal("author_first", BookInfoManager:getSetting("author_series_order"))
        assert.equal("right", BookInfoManager:getSetting("footer_page_controls_alignment"))
        assert.equal("all", BookInfoManager:getSetting("library_status_filter"))
        assert.is_true(state.made_true["aaaProjectTitle_initial_default_setup_done2"])
    end)

    it("runs the real version 5 migration and preserves the pages-based progress mode", function()
        local main, _, BookInfoManager = main_loader.load_main({
            initial_setup_done = true,
        })
        BookInfoManager:saveSetting("config_version", 5)
        BookInfoManager:saveSetting("show_pages_read_as_progress", true)

        local restart_needed = main._runSettingsMigrations()

        assert.is_false(restart_needed)
        assert.equal(12, BookInfoManager:getSetting("config_version"))
        assert.equal("status_and_pages", BookInfoManager:getSetting("progress_text_format"))
        assert.equal("Y", BookInfoManager:getSetting("show_mosaic_titles"))
        assert.equal("author_first", BookInfoManager:getSetting("author_series_order"))
        assert.equal("all", BookInfoManager:getSetting("library_status_filter"))
    end)

    it("runs the real version 9 migration and derives footer alignment from reverse_footer", function()
        local main, _, BookInfoManager = main_loader.load_main({
            initial_setup_done = true,
        })
        BookInfoManager:saveSetting("config_version", 9)
        BookInfoManager:saveSetting("reverse_footer", true)

        local restart_needed = main._runSettingsMigrations()

        assert.is_false(restart_needed)
        assert.equal(12, BookInfoManager:getSetting("config_version"))
        assert.equal("left", BookInfoManager:getSetting("footer_page_controls_alignment"))
        assert.equal("Y", BookInfoManager:getSetting("footer_show_clock"))
        assert.equal("Y", BookInfoManager:getSetting("footer_show_wifi"))
        assert.equal("Y", BookInfoManager:getSetting("footer_show_battery"))
        assert.equal("Y", BookInfoManager:getSetting("footer_show_frontlight"))
        assert.equal("Y", BookInfoManager:getSetting("footer_show_frontlight_warmth"))
        assert.equal("all", BookInfoManager:getSetting("library_status_filter"))
    end)

    it("migrates an unversioned existing install through the full chain", function()
        local main, _, BookInfoManager = main_loader.load_main({
            initial_setup_done = true,
        })
        BookInfoManager:saveSetting("config_version", nil)

        local restart_needed = main._runSettingsMigrations()

        assert.is_true(restart_needed)
        assert.equal(12, BookInfoManager:getSetting("config_version"))
        assert.equal("status_and_percent", BookInfoManager:getSetting("progress_text_format"))
        assert.equal("author_first", BookInfoManager:getSetting("author_series_order"))
        assert.equal("right", BookInfoManager:getSetting("footer_page_controls_alignment"))
        assert.equal("all", BookInfoManager:getSetting("library_status_filter"))
    end)
end)

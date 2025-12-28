local config = require("ensure.config")

describe("ensure.config", function()
    it("returns defaults when called without opts", function()
        local cfg = config.setup()

        assert.is_false(cfg.install)
        assert.same({}, cfg.packages)
        assert.same({ auto = true }, cfg.parsers)
        assert.same({ auto = false, clear = false }, cfg.formatters)
        assert.same({ auto = false, clear = false }, cfg.linters)
        assert.same({ enable = {}, disable = {}, auto = false, clear = false }, cfg.lsp)

        local default_plugins = {
            "ensure.plugin.mason",
            "ensure.plugin.lsp",
            "ensure.plugin.treesitter",
            "ensure.plugin.conform",
            "ensure.plugin.lint",
        }
        assert.same(default_plugins, cfg.plugins)
    end)

    it("merges shallow overrides", function()
        local cfg = config.setup({ install = true })

        assert.is_true(cfg.install)

        local default_plugins = {
            "ensure.plugin.mason",
            "ensure.plugin.lsp",
            "ensure.plugin.treesitter",
            "ensure.plugin.conform",
            "ensure.plugin.lint",
        }
        assert.same(default_plugins, cfg.plugins)
    end)

    it("overrides plugins from opts", function()
        local cfg = config.setup({ plugins = { "a", "b" } })

        assert.same({ "a", "b" }, cfg.plugins)
    end)

    it("get_plugins returns plugins from last setup", function()
        config.setup({ plugins = { "x", "y" } })
        local plugins = config.get_plugins()

        assert.same({ "x", "y" }, plugins)
    end)
end)

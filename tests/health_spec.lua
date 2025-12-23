local helpers = require("tests.helpers")

describe("ensure.health #health", function()
    before_each(function()
        helpers.mock(vim.health, true)
    end)

    after_each(function()
        helpers.teardown()
    end)

    local config = require("ensure.config")
    local health = require("ensure.health")

    it("reports lazy as installed when available", function()
        helpers.stub(config, "get_plugins", {})

        health.check()

        assert.stub(vim.health.start).was_called_with("ensure")
        assert.stub(vim.health.ok).was_called_with("`lazy.nvim` is installed")
    end)

    it("warns when lazy is not installed", function()
        helpers.modules_not_found("lazy")
        helpers.stub(config, "get_plugins", {})

        health.check()

        assert.stub(vim.health.start).was_called_with("ensure")
        assert.stub(vim.health.warn).was_called_with("`lazy.nvim` is not installed, `opts` merging not available")
    end)

    it("delegates health checks to plugins", function()
        helpers.stub(config, "get_plugins", { "plugin.one", "plugin.two" })
        local plugin1 = helpers.plugin("plugin.one")
        local plugin2 = helpers.plugin("plugin.two")

        health.check()

        assert.stub(plugin1.methods.health).was_called_with(match.is_ref(plugin1))
        assert.stub(plugin2.methods.health).was_called_with(match.is_ref(plugin2))
    end)
end)

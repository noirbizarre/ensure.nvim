local helpers = require("spec.helpers")

describe("ensure.command", function()
    before_each(function()
        helpers.stub(vim, "notify")
    end)

    after_each(function()
        helpers.teardown()
    end)

    local ensure = require("ensure")
    local config = require("ensure.config")
    local command = require("ensure.command")

    it("calls ensure.install when no arguments are provided", function()
        helpers.stub(ensure, "install")

        command({ bang = false, fargs = {} })

        assert.stub(ensure.install).was_called_with({ all = false })
        assert.stub(vim.notify).was_not_called()
    end)

    it("passes bang to ensure.install", function()
        helpers.stub(ensure, "install")

        command({ bang = true, fargs = {} })

        assert.stub(ensure.install).was_called_with({ all = true })
        assert.stub(vim.notify).was_not_called()
    end)

    it("dispatches to plugin subcommand when known", function()
        helpers.stub(config, "get_plugins", { "plugin.one", "plugin.two" })
        local plugin1 = helpers.plugin("plugin.one", { command = "plugin1" })
        local plugin2 = helpers.plugin("plugin.two", { command = "plugin2" })

        command({ bang = true, fargs = { "plugin1" } })

        assert.stub(plugin1.methods.install).was_called_with(match.is_ref(plugin1), { all = true })
        assert.stub(plugin2.methods.install).was_not_called()
    end)

    it("notifies on unknown subcommand", function()
        helpers.stub(config, "get_plugins", { "plugin" })
        local plugin = helpers.plugin("plugin", { command = "known" })

        command({ bang = false, fargs = { "unknown" } })

        assert.stub(vim.notify).was_called()
        assert
            .stub(vim.notify)
            .was_called_with(
                "Unknown argument: `unknown`\nMust be one of [all, install, known].",
                vim.log.levels.ERROR,
                match.is_table()
            )
    end)
end)

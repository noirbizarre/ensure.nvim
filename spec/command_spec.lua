local helpers = require("spec.helpers")

describe("ensure.command", function()
    local auto = require("ensure.auto")

    before_each(function()
        helpers.stub(vim, "notify")
        auto.reset()
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
        helpers.plugin("plugin", { command = "known" })

        command({ bang = false, fargs = { "unknown" } })

        assert.stub(vim.notify).was_called()
        assert.stub(vim.notify).was_called_with(
            "Unknown argument: `unknown`\nMust be one of [all, install, known, session].",
            vim.log.levels.ERROR,
            match.is_table()
        )
    end)

    describe("session subcommand", function()
        describe("session clear", function()
            it("clears session choices", function()
                -- Set up some session choices
                vim.g.EnsureAutoChoices = vim.json.encode({
                    Formatter = { lua = { tool = "stylua", package = "stylua" } },
                })

                command({ bang = false, fargs = { "session", "clear" } })

                assert.is_nil(vim.g.EnsureAutoChoices)
                assert.stub(vim.notify).was_called()
            end)
        end)

        describe("session dump", function()
            it("warns when no choices exist", function()
                command({ bang = false, fargs = { "session", "dump" } })

                assert
                    .stub(vim.notify)
                    .was_called_with("No session choices to dump", vim.log.levels.WARN, match.is_table())
            end)

            it("outputs LSP configuration", function()
                vim.g.EnsureAutoChoices = vim.json.encode({
                    ["LSP server"] = {
                        lua = { tool = "lua_ls", package = "lua-language-server" },
                        python = { tool = "pyright", package = "pyright" },
                    },
                })

                command({ bang = false, fargs = { "session", "dump" } })

                assert.stub(vim.notify).was_called()
                local call_args = vim.notify.calls[1].vals[1]
                assert.matches("lsp = {", call_args)
                assert.matches('enable = { "lua_ls", "pyright" }', call_args)
            end)

            it("outputs formatter configuration", function()
                vim.g.EnsureAutoChoices = vim.json.encode({
                    Formatter = {
                        lua = { tool = "stylua", package = "stylua" },
                        python = { tool = "black", package = "black" },
                    },
                })

                command({ bang = false, fargs = { "session", "dump" } })

                assert.stub(vim.notify).was_called()
                local call_args = vim.notify.calls[1].vals[1]
                assert.matches("formatters = {", call_args)
                assert.matches('lua = "stylua"', call_args)
                assert.matches('python = "black"', call_args)
            end)

            it("outputs linter configuration", function()
                vim.g.EnsureAutoChoices = vim.json.encode({
                    Linter = {
                        python = { tool = "ruff", package = "ruff" },
                    },
                })

                command({ bang = false, fargs = { "session", "dump" } })

                assert.stub(vim.notify).was_called()
                local call_args = vim.notify.calls[1].vals[1]
                assert.matches("linters = {", call_args)
                assert.matches('python = "ruff"', call_args)
            end)

            it("outputs combined configuration", function()
                vim.g.EnsureAutoChoices = vim.json.encode({
                    ["LSP server"] = { lua = { tool = "lua_ls", package = "lua-language-server" } },
                    Formatter = { lua = { tool = "stylua", package = "stylua" } },
                    Linter = { python = { tool = "ruff", package = "ruff" } },
                })

                command({ bang = false, fargs = { "session", "dump" } })

                assert.stub(vim.notify).was_called()
                local call_args = vim.notify.calls[1].vals[1]
                assert.matches("lsp = {", call_args)
                assert.matches("formatters = {", call_args)
                assert.matches("linters = {", call_args)
            end)
        end)

        it("notifies on unknown session subcommand", function()
            command({ bang = false, fargs = { "session", "unknown" } })

            assert.stub(vim.notify).was_called()
            assert.stub(vim.notify).was_called_with(
                "Unknown session subcommand: `unknown`\nMust be one of [clear, dump].",
                vim.log.levels.ERROR,
                match.is_table()
            )
        end)

        it("notifies when session subcommand is missing", function()
            command({ bang = false, fargs = { "session" } })

            assert.stub(vim.notify).was_called()
            assert
                .stub(vim.notify)
                .was_called_with(
                    "Unknown session subcommand: `nil`\nMust be one of [clear, dump].",
                    vim.log.levels.ERROR,
                    match.is_table()
                )
        end)
    end)
end)

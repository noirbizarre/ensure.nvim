local helpers = require("tests.helpers")

describe("ensure.plugin.lsp #plugin #lsp", function()
    before_each(function()
        helpers.mock(vim.health, true)
    end)

    after_each(function()
        helpers.teardown()
    end)

    local mason = require("ensure.plugin.mason")
    local plugin = require("ensure.plugin.lsp")

    it("enables configured LSPs minus disabled ones and configures extra entries", function()
        helpers.stub(vim.lsp, "enable")
        helpers.stub(vim.lsp, "config")

        ---@diagnostic disable-next-line: missing-fields
        plugin:setup({
            lsp = {
                enable = { "lua_ls", "pyright" },
                disable = { "pyright" },
                lua_ls = { settings = { foo = true } },
                jsonls = function()
                    return { settings = { bar = true } }
                end,
            },
        })

        assert.stub(vim.lsp.enable).was_called_with({ "lua_ls" })
        assert.stub(vim.lsp.config).was_called_with("lua_ls", match.is_table())
        assert.stub(vim.lsp.config).was_called_with("jsonls", match.is_table())
    end)

    it("health checks neovim version and mason plugin #health", function()
        mason.is_enabled = true
        helpers.stub(vim.fn, "has", 1)

        plugin:health()

        assert.stub(vim.health.ok).was_called_with("Using `Neovim >= 0.11.0`")
        assert.stub(vim.health.ok).was_called_with("`ensure.plugin.mason` plugin is enabled")
    end)

    it("health errors when neovim version too old #health", function()
        helpers.stub(vim.fn, "has", 0)

        plugin:health()

        assert.stub(vim.health.error).was_called_with("`Neovim >= 0.11.0` is required")
    end)

    it("autoinstall installs LSP packages via mason for matching filetype", function()
        mason.is_enabled = true
        -- mason_plugin.install_packages = function() end
        helpers.stub(mason, "install_packages")

        vim.lsp._enabled_configs = {
            lua_ls = {
                resolved_config = { filetypes = { "lua", "vim" } },
            },
            ts_ls = {
                resolved_config = { filetypes = { "typescript" } },
            },
        }

        plugin.lsp_to_mason = { lua_ls = "lua-language-server" }
        plugin.mason_to_lsp = { ["lua-language-server"] = "lua_ls" }

        plugin:autoinstall("lua")

        assert
            .stub(mason.install_packages)
            .was_called_with(match.ref(mason), { "lua-language-server" }, match.is_function())
    end)
end)

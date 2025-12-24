local helpers = require("tests.helpers")

describe("ensure.plugin.lsp", function()
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

    it("health checks neovim version and mason plugin", function()
        mason.is_enabled = true
        helpers.stub(vim.fn, "has", 1)

        plugin:health()

        assert.stub(vim.health.ok).was_called_with("Using `Neovim >= 0.11.0`")
        assert.stub(vim.health.ok).was_called_with("`ensure.plugin.mason` plugin is enabled")
    end)

    it("health errors when neovim version too old", function()
        helpers.stub(vim.fn, "has", 0)

        plugin:health()

        assert.stub(vim.health.error).was_called_with("`Neovim >= 0.11.0` is required")
    end)

    it("autoinstall installs LSP packages via mason for matching filetype", function()
        mason.is_enabled = true
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

    it("autoinstall does nothing when mason is not enabled", function()
        mason.is_enabled = false
        helpers.stub(mason, "install_packages")

        plugin:autoinstall("lua")

        assert.stub(mason.install_packages).was_not_called()
    end)

    it("health errors when mason plugin not enabled", function()
        mason.is_enabled = false
        helpers.stub(vim.fn, "has", 1)

        plugin:health()

        assert.stub(vim.health.ok).was_called_with("Using `Neovim >= 0.11.0`")
        assert
            .stub(vim.health.error)
            .was_called_with("`ensure.plugin.mason` plugin is not enabled, LSPs won't be installed")
    end)

    it("build_mapping populates lsp_to_mason and mason_to_lsp from registry specs", function()
        local registry = require("mason-registry")
        helpers.stub(registry, "get_all_package_specs", {
            { name = "lua-language-server", neovim = { lspconfig = "lua_ls" } },
            { name = "pyright", neovim = { lspconfig = "pyright" } },
            { name = "some-tool", neovim = {} },
            { name = "another-tool" },
        })

        plugin:build_mapping()

        assert.same({ lua_ls = "lua-language-server", pyright = "pyright" }, plugin.lsp_to_mason)
        assert.same({ ["lua-language-server"] = "lua_ls", pyright = "pyright" }, plugin.mason_to_lsp)
    end)

    it("install installs enabled LSP packages via mason", function()
        mason.is_enabled = true
        helpers.stub(mason, "install_packages")

        vim.lsp._enabled_configs = {
            lua_ls = {},
            pyright = {},
        }

        plugin.lsp_to_mason = { lua_ls = "lua-language-server" }
        plugin.mason_to_lsp = { ["lua-language-server"] = "lua_ls" }

        plugin:install()

        assert.stub(mason.install_packages).was_called_with(match.ref(mason), match.is_table(), match.is_function())
    end)

    it("install with all=true installs all configured LSPs", function()
        mason.is_enabled = true
        helpers.stub(mason, "install_packages")

        vim.lsp._enabled_configs = { lua_ls = {} }
        vim.lsp.config._configs = {
            lua_ls = {},
            jsonls = {},
            pyright = {},
        }

        plugin.lsp_to_mason = { lua_ls = "lua-language-server" }
        plugin.mason_to_lsp = { ["lua-language-server"] = "lua_ls" }

        plugin:install({ all = true })

        assert.stub(mason.install_packages).was_called_with(match.ref(mason), match.is_table(), match.is_function())
    end)

    it("install does nothing when mason not enabled", function()
        mason.is_enabled = false
        helpers.stub(mason, "install_packages")

        plugin:install()

        assert.stub(mason.install_packages).was_not_called()
    end)

    it("setup builds mapping when mason is enabled", function()
        mason.is_enabled = true
        helpers.stub(vim.lsp, "enable")
        helpers.stub(vim.lsp, "config")
        helpers.stub(plugin, "build_mapping")

        local registry = require("mason-registry")
        helpers.stub(registry, "on")

        ---@diagnostic disable-next-line: missing-fields
        plugin:setup({ lsp = { enable = {}, disable = {} } })

        assert.stub(plugin.build_mapping).was_called()
        assert.stub(registry.on).was_called_with(match.ref(registry), "update:success", match.is_function())
    end)

    it("setup does not build mapping when mason is disabled", function()
        mason.is_enabled = false
        helpers.stub(vim.lsp, "enable")
        helpers.stub(vim.lsp, "config")
        helpers.stub(plugin, "build_mapping")

        ---@diagnostic disable-next-line: missing-fields
        plugin:setup({ lsp = { enable = {}, disable = {} } })

        assert.stub(plugin.build_mapping).was_not_called()
    end)
end)

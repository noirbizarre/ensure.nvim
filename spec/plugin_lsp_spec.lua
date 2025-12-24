local helpers = require("spec.helpers")

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

        -- Mock resolve_package to return expected mappings
        helpers.stub(plugin, "resolve_package", function(_, lsp_name)
            local mapping = { lua_ls = "lua-language-server" }
            return mapping[lsp_name]
        end)

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

    it("install installs enabled LSP packages via mason", function()
        mason.is_enabled = true
        helpers.stub(mason, "install_packages")

        vim.lsp._enabled_configs = {
            lua_ls = {},
            pyright = {},
        }

        -- Mock resolve_package to return expected mappings
        helpers.stub(plugin, "resolve_package", function(_, lsp_name)
            local mapping = { lua_ls = "lua-language-server", pyright = "pyright" }
            return mapping[lsp_name]
        end)

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

        -- Mock resolve_package to return expected mappings
        helpers.stub(plugin, "resolve_package", function(_, lsp_name)
            local mapping = { lua_ls = "lua-language-server", jsonls = "json-lsp", pyright = "pyright" }
            return mapping[lsp_name]
        end)

        plugin:install({ all = true })

        assert.stub(mason.install_packages).was_called_with(match.ref(mason), match.is_table(), match.is_function())
    end)

    it("install does nothing when mason not enabled", function()
        mason.is_enabled = false
        helpers.stub(mason, "install_packages")

        plugin:install()

        assert.stub(mason.install_packages).was_not_called()
    end)

    describe("resolve_package", function()
        it("returns nil when LSP command is already executable", function()
            vim.lsp.config._configs = {
                lua_ls = { cmd = { "lua-language-server" } },
            }

            mason.is_enabled = true
            helpers.stub(vim.fn, "executable", 1)
            helpers.stub(mason, "resolve_tool", "lua-language-server")

            local result = plugin:resolve_package("lua_ls")

            assert.is_nil(result)
            assert.stub(mason.resolve_tool).was_not_called()
        end)

        it("returns package name from mason resolve_lsp when LSP command is not executable", function()
            vim.lsp.config._configs = {
                lua_ls = { cmd = { "lua-language-server" } },
            }

            mason.is_enabled = true
            helpers.stub(vim.fn, "executable", 0)
            helpers.stub(mason, "resolve_lsp", "lua-language-server")

            local result = plugin:resolve_package("lua_ls")

            assert.same("lua-language-server", result)
            assert.stub(mason.resolve_lsp).was_called_with(match.ref(mason), "lua_ls")
        end)

        it("returns nil when mason is not enabled", function()
            mason.is_enabled = false

            local result = plugin:resolve_package("lua_ls")

            assert.is_nil(result)
        end)

        it("returns nil when LSP config has no cmd", function()
            vim.lsp.config._configs = {
                no_cmd = {},
            }

            mason.is_enabled = true
            helpers.stub(mason, "resolve_lsp", nil)
            helpers.stub(mason, "resolve_tool", nil)
            helpers.stub(mason, "resolve", false)

            local result = plugin:resolve_package("no_cmd")

            assert.is_nil(result)
        end)

        it("returns nil when LSP is not configured", function()
            vim.lsp.config._configs = {}

            mason.is_enabled = true
            helpers.stub(mason, "resolve_lsp", nil)
            helpers.stub(mason, "resolve_tool", nil)
            helpers.stub(mason, "resolve", false)

            local result = plugin:resolve_package("unknown_lsp")

            assert.is_nil(result)
        end)

        it("handles cmd as function", function()
            vim.lsp.config._configs = {
                dynamic_lsp = {
                    cmd = function()
                        return { "dynamic-server" }
                    end,
                },
            }

            mason.is_enabled = true
            helpers.stub(vim.fn, "executable", 0)
            helpers.stub(mason, "resolve_lsp", "dynamic-pkg")

            local result = plugin:resolve_package("dynamic_lsp")

            assert.same("dynamic-pkg", result)
        end)

        it("returns nil when cmd function returns executable command", function()
            vim.lsp.config._configs = {
                dynamic_lsp = {
                    cmd = function()
                        return { "available-server" }
                    end,
                },
            }

            mason.is_enabled = true
            helpers.stub(vim.fn, "executable", 1)
            helpers.stub(mason, "resolve_tool", "dynamic-pkg")

            local result = plugin:resolve_package("dynamic_lsp")

            assert.is_nil(result)
            assert.stub(mason.resolve_tool).was_not_called()
        end)

        it("falls back to mason resolve_tool when resolve_lsp returns nil", function()
            vim.lsp.config._configs = {
                pyright = { cmd = { "pyright-langserver" } },
            }

            mason.is_enabled = true
            helpers.stub(vim.fn, "executable", 0)
            helpers.stub(mason, "resolve_lsp", nil)
            helpers.stub(mason, "resolve_tool", "pyright")

            local result = plugin:resolve_package("pyright")

            assert.same("pyright", result)
            assert.stub(mason.resolve_tool).was_called_with(match.ref(mason), "pyright")
        end)

        it("falls back to mason resolve when resolve_lsp and resolve_tool return nil", function()
            vim.lsp.config._configs = {
                custom_lsp = { cmd = { "custom-server" } },
            }

            mason.is_enabled = true
            helpers.stub(vim.fn, "executable", 0)
            helpers.stub(mason, "resolve_lsp", nil)
            helpers.stub(mason, "resolve_tool", nil)
            helpers.stub(mason, "resolve", true)

            local result = plugin:resolve_package("custom_lsp")

            assert.same("custom_lsp", result)
            assert.stub(mason.resolve).was_called_with(match.ref(mason), "custom_lsp")
        end)

        it("returns nil when no resolution method finds package", function()
            vim.lsp.config._configs = {
                unknown_lsp = { cmd = { "unknown-server" } },
            }

            mason.is_enabled = true
            helpers.stub(vim.fn, "executable", 0)
            helpers.stub(mason, "resolve_lsp", nil)
            helpers.stub(mason, "resolve_tool", nil)
            helpers.stub(mason, "resolve", false)

            local result = plugin:resolve_package("unknown_lsp")

            assert.is_nil(result)
        end)
    end)
end)

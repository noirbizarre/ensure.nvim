local helpers = require("spec.helpers")

describe("ensure.plugin.lint", function()
    before_each(function()
        helpers.mock(vim.health, true)
    end)

    after_each(function()
        helpers.teardown()
    end)

    local mason = require("ensure.plugin.mason")
    local plugin = require("ensure.plugin.lint")

    it("setup populates lint.linters_by_ft using util.string_list", function()
        local lint = require("lint")
        lint.linters_by_ft = {}

        ---@diagnostic disable-next-line: missing-fields
        plugin:setup({
            linters = {
                lua = "selene",
                python = { "ruff" },
            },
        })

        assert.is_true(plugin.is_installed)
        assert.same({ "selene" }, lint.linters_by_ft.lua)
        assert.same({ "ruff" }, lint.linters_by_ft.python)
    end)

    it("setup does nothing when lint is not installed", function()
        local lint = require("lint")
        lint.linters_by_ft = {}

        helpers.modules_not_found("lint")

        ---@diagnostic disable-next-line: missing-fields
        plugin:setup({
            linters = {
                lua = "selene",
            },
        })

        assert.is_false(plugin.is_installed)
        assert.is.same(lint.linters_by_ft, {})
    end)

    it("health reports install state and mason plugin enabled/disabled", function()
        mason.is_enabled = true
        plugin.is_installed = true

        plugin:health()

        assert.stub(vim.health.ok).was_called_with("`nvim-lint` is installed")
        assert.stub(vim.health.ok).was_called_with("`ensure.plugin.mason` plugin is enabled")

        mason.is_enabled = false
        plugin:health()
        assert
            .stub(vim.health.warn)
            .was_called_with("`ensure.plugin.mason` plugin is not enabled, linters won't be installed")
    end)

    it("autoinstall resolves linters to mason packages and installs them", function()
        local lint = require("lint")
        lint.linters_by_ft = { lua = { "mh_lint", "other" } }

        mason.is_enabled = true
        helpers.stub(mason, "install_packages")
        plugin.is_installed = true

        -- Mock resolve_package to return expected mappings
        helpers.stub(plugin, "resolve_package", function(_, linter_name)
            local mapping = { mh_lint = "miss_hit", other = "other" }
            return mapping[linter_name]
        end)

        plugin:autoinstall("lua")

        assert.stub(mason.install_packages).was_called_with(match.ref(mason), { "miss_hit", "other" })
    end)

    it("install installs all configured linters via mason", function()
        local lint = require("lint")
        lint.linters_by_ft = {
            lua = { "mh_lint" },
            python = { "buf_lint", "foo" },
        }

        mason.is_enabled = true
        helpers.stub(mason, "install_packages")
        helpers.stub(mason, "install_package")
        plugin.is_installed = true

        -- Mock resolve_package to return expected mappings
        helpers.stub(plugin, "resolve_package", function(_, linter_name)
            local mapping = { mh_lint = "miss_hit", buf_lint = "buf", foo = "foo" }
            return mapping[linter_name]
        end)

        plugin:install()

        assert
            .stub(mason.install_packages)
            .was_called_with(match.ref(mason), match.table_with({ "miss_hit", "buf", "foo" }))
    end)

    it("health errors when nvim-lint not installed", function()
        plugin.is_installed = false
        mason.is_enabled = true

        plugin:health()

        assert.stub(vim.health.error).was_called_with("`nvim-lint` is not installed")
    end)

    it("autoinstall does nothing when lint not installed", function()
        plugin.is_installed = false
        mason.is_enabled = true
        helpers.stub(mason, "install_packages")

        plugin:autoinstall("lua")

        assert.stub(mason.install_packages).was_not_called()
    end)

    it("autoinstall does nothing when mason not enabled", function()
        plugin.is_installed = true
        mason.is_enabled = false
        helpers.stub(mason, "install_packages")

        plugin:autoinstall("lua")

        assert.stub(mason.install_packages).was_not_called()
    end)

    it("install does nothing when lint not installed", function()
        plugin.is_installed = false
        mason.is_enabled = true
        helpers.stub(mason, "install_packages")

        plugin:install()

        assert.stub(mason.install_packages).was_not_called()
    end)

    it("install does nothing when mason not enabled", function()
        local lint = require("lint")
        lint.linters_by_ft = { lua = { "selene" } }

        plugin.is_installed = true
        mason.is_enabled = false
        helpers.stub(mason, "install_packages")

        plugin:install()

        assert.stub(mason.install_packages).was_not_called()
    end)

    describe("resolve_package", function()
        it("returns nil when linter command is already executable", function()
            local lint = require("lint")
            lint.linters = {
                selene = { cmd = "selene" },
            }

            mason.is_enabled = true
            helpers.stub(mason, "resolve_tool", "selene")
            helpers.stub(vim.fn, "executable", 1)

            local result = plugin:resolve_package("selene")

            assert.is_nil(result)
            assert.stub(mason.resolve_tool).was_not_called()
        end)

        it("returns package name when linter command is not executable", function()
            local lint = require("lint")
            lint.linters = {
                selene = { cmd = "selene" },
            }

            mason.is_enabled = true
            helpers.stub(mason, "resolve_tool", "selene")
            helpers.stub(vim.fn, "executable", 0)

            local result = plugin:resolve_package("selene")

            assert.same("selene", result)
            assert.stub(mason.resolve_tool).was_called_with(match.ref(mason), "selene")
        end)

        it("returns nil when mason is not enabled", function()
            mason.is_enabled = false

            local result = plugin:resolve_package("selene")

            assert.is_nil(result)
        end)

        it("returns nil when linter is not found", function()
            local lint = require("lint")
            lint.linters = {}

            mason.is_enabled = true

            local result = plugin:resolve_package("unknown")

            assert.is_nil(result)
        end)

        it("returns nil when linter has no cmd", function()
            local lint = require("lint")
            lint.linters = {
                nocmd = {},
            }

            mason.is_enabled = true

            local result = plugin:resolve_package("nocmd")

            assert.is_nil(result)
        end)

        it("handles linter as factory function", function()
            local lint = require("lint")
            lint.linters = {
                factory_linter = function()
                    return { cmd = "factory-cmd" }
                end,
            }

            mason.is_enabled = true
            helpers.stub(mason, "resolve_tool", "factory-pkg")
            helpers.stub(vim.fn, "executable", 0)

            local result = plugin:resolve_package("factory_linter")

            assert.same("factory-pkg", result)
            assert.stub(mason.resolve_tool).was_called_with(match.ref(mason), "factory-cmd")
        end)

        it("handles cmd as function", function()
            local lint = require("lint")
            lint.linters = {
                dynamic_cmd = {
                    cmd = function()
                        return "dynamic-executable"
                    end,
                },
            }

            mason.is_enabled = true
            helpers.stub(mason, "resolve_tool", "dynamic-pkg")
            helpers.stub(vim.fn, "executable", 0)

            local result = plugin:resolve_package("dynamic_cmd")

            assert.same("dynamic-pkg", result)
            assert.stub(mason.resolve_tool).was_called_with(match.ref(mason), "dynamic-executable")
        end)

        it("extracts executable name from full path", function()
            local lint = require("lint")
            lint.linters = {
                fullpath = { cmd = "/home/user/.local/bin/my-linter" },
            }

            mason.is_enabled = true
            helpers.stub(mason, "resolve_tool", "my-linter-pkg")
            helpers.stub(vim.fn, "executable", 0)

            plugin:resolve_package("fullpath")

            assert.stub(mason.resolve_tool).was_called_with(match.ref(mason), "my-linter")
        end)
    end)
end)

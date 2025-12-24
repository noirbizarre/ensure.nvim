local helpers = require("tests.helpers")

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

    it("autoinstall installs mapped linters for filetype", function()
        local lint = require("lint")
        lint.linters_by_ft = { lua = { "mh_lint", "other" } }

        mason.is_enabled = true
        helpers.stub(mason, "install_packages")
        plugin.is_installed = true

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
end)

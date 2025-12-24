local helpers = require("tests.helpers")

describe("ensure.plugin.conform", function()
    before_each(function()
        helpers.mock(vim.health, true)
    end)

    after_each(function()
        helpers.teardown()
    end)

    local mason = require("ensure.plugin.mason")
    local plugin = require("ensure.plugin.conform")

    it("setup does nothing when conform is not installed", function()
        helpers.modules_not_found("conform")

        ---@diagnostic disable-next-line: missing-fields
        plugin:setup({ formatters = { lua = { "stylua" } } })

        assert.is_false(plugin.is_installed)
    end)

    it("setup registers formatters by filetype using util.string_list", function()
        local conform = require("conform")
        conform.formatters_by_ft = {}

        ---@diagnostic disable-next-line: missing-fields
        plugin:setup({
            formatters = {
                lua = "stylua",
                python = { "ruff_format" },
            },
        })

        assert.is_true(plugin.is_installed)
        assert.same({ "stylua" }, conform.formatters_by_ft.lua)
        assert.same({ "ruff_format" }, conform.formatters_by_ft.python)
    end)

    it("autoinstall maps formatters to mason packages and calls install_packages", function()
        local conform = require("conform")
        helpers.stub(conform, "list_formatters_for_buffer", { "ruff_fix", "prettier" })

        mason.is_enabled = true
        helpers.stub(mason, "install_packages")
        plugin.is_installed = true

        helpers.stub(vim.api, "nvim_get_current_buf", 1)

        plugin:autoinstall("lua")

        assert.stub(mason.install_packages).was_called_with(match.ref(mason), { "ruff", "prettier" })
    end)

    it("health reports conform installed and mason enabled", function()
        plugin.is_installed = true
        mason.is_enabled = true

        plugin:health()

        assert.stub(vim.health.ok).was_called_with("`conform.nvim` is installed")
        assert.stub(vim.health.ok).was_called_with("`ensure.plugin.mason` plugin is enabled")
    end)

    it("health errors when conform not installed", function()
        plugin.is_installed = false
        mason.is_enabled = true

        plugin:health()

        assert.stub(vim.health.error).was_called_with("`conform.nvim` is not installed")
    end)

    it("health warns when mason plugin not enabled", function()
        plugin.is_installed = true
        mason.is_enabled = false

        plugin:health()

        assert.stub(vim.health.ok).was_called_with("`conform.nvim` is installed")
        assert
            .stub(vim.health.warn)
            .was_called_with("`ensure.plugin.mason` plugin is not enabled, formatters won't be installed")
    end)

    it("install installs all known formatters via mason", function()
        local conform = require("conform")
        conform.formatters_by_ft = {
            lua = { "stylua" },
            python = { "ruff_format" },
            unknown = { "unknown_formatter" },
        }

        mason.is_enabled = true
        helpers.stub(mason, "install_packages")
        plugin.is_installed = true

        plugin:install()

        assert.stub(mason.install_packages).was_called_with(
            match.ref(mason),
            match.is_all_of(match.table_with({ "stylua", "ruff" }), match.table_without({ "unknown_formatter" }))
        )
    end)

    it("install does nothing when mason not enabled", function()
        mason.is_enabled = false
        helpers.stub(mason, "install_packages")
        plugin.is_installed = true

        plugin:install()

        assert.stub(mason.install_packages).was_not_called()
    end)

    it("install does nothing when conform not installed", function()
        mason.is_enabled = true
        helpers.stub(mason, "install_packages")
        plugin.is_installed = false

        plugin:install()

        assert.stub(mason.install_packages).was_not_called()
    end)
end)

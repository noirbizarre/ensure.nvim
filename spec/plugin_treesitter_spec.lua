local helpers = require("spec.helpers")
local match = require("luassert.match")

describe("ensure.plugin.treesitter", function()
    before_each(function()
        helpers.mock(vim.health, true)
    end)

    after_each(function()
        helpers.teardown()
    end)

    local ts = require("nvim-treesitter")
    local plugin = require("ensure.plugin.treesitter")

    it("setup stores parsers/ignore and triggers install when nvim-treesitter is available", function()
        helpers.stub(ts, "install")

        ---@diagnostic disable-next-line: missing-fields
        plugin:setup({
            parsers = { "lua", "rust" },
            ---@diagnostic disable-next-line: missing-fields
            ignore = { parsers = { "rust" } },
        })

        assert.is_true(plugin.is_installed)
        assert.same({ "lua", "rust" }, plugin.parsers)
        assert.same({ "rust" }, plugin.ignore)

        -- Wait for vim.schedule callbacks to execute
        helpers.flush_schedule()

        assert.stub(ts.install).was_called_with({ "lua" })
    end)

    it("health reports missing nvim-treesitter", function()
        plugin.is_installed = false

        plugin:health()

        assert.stub(vim.health.error).was_called_with("`nvim-treesitter` is not installed")
    end)

    it("autoinstalls parser for current filetype when available and not ignored", function()
        helpers.stub(ts, "install")

        plugin.is_installed = true
        plugin.ignore = { "rust" }

        plugin:autoinstall("python")
        assert.stub(ts.install).was_called_with({ "python" })

        ts.install:clear()
        plugin:autoinstall("rust")
        assert.stub(ts.install).was_not_called()
    end)

    it("installs missing, non-ignored parsers", function()
        helpers.stub(ts, "install")

        plugin.is_installed = true
        plugin.parsers = { "lua", "python", "rust" }
        plugin.ignore = { "rust" }

        plugin:install()

        assert.stub(ts.install).was_called_with({ "lua", "python" })
    end)

    it("installs all available parser with all=true and respect ignore", function()
        plugin.is_installed = true
        plugin.ignore = { "rust" }

        helpers.stub(ts, "install")
        helpers.stub(ts, "get_available", function(tier)
            if tier == 1 then
                return { "python", "rust" }
            elseif tier == 2 then
                return { "go" }
            elseif tier >= 3 then
                return { "typescript" }
            else
                return { "python", "go", "rust", "typescript" }
            end
        end)

        plugin:install({ all = true })

        assert.stub(ts.install).was_called_with({ "python", "go" })
    end)

    it("health reports nvim-treesitter installed with main branch", function()
        plugin.is_installed = true

        plugin:health()

        assert.stub(vim.health.ok).was_called_with("`nvim-treesitter` is installed")
        assert.stub(vim.health.ok).was_called_with("Using `main` branch of `nvim-treesitter`")
    end)

    it("health errors when using master branch of nvim-treesitter", function()
        plugin.is_installed = true
        local original_install = ts.install
        ts.install = nil
        finally(function()
            ts.install = original_install
        end)

        plugin:health()

        assert.stub(vim.health.ok).was_called_with("`nvim-treesitter` is installed")
        assert
            .stub(vim.health.error)
            .was_called_with("Using `master` branch of `nvim-treesitter`, `main` branch is required")
    end)

    it("setup does nothing when nvim-treesitter is not installed", function()
        helpers.modules_not_found("nvim-treesitter")

        ---@diagnostic disable-next-line: missing-fields
        plugin:setup({
            parsers = { "lua" },
            ---@diagnostic disable-next-line: missing-fields
            ignore = { parsers = {} },
        })

        assert.is_false(plugin.is_installed)
    end)

    it("autoinstall does nothing when nvim-treesitter is not installed", function()
        plugin.is_installed = false
        helpers.stub(ts, "install")

        plugin:autoinstall("lua")

        assert.stub(ts.install).was_not_called()
    end)

    it("install does nothing when nvim-treesitter is not installed", function()
        plugin.is_installed = false
        helpers.stub(ts, "install")

        plugin:install()

        assert.stub(ts.install).was_not_called()
    end)
end)

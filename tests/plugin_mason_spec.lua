local helpers = require("tests.helpers")
local match = require("luassert.match")

describe("ensure.plugin.mason #plugin #mason", function()
    before_each(function()
        helpers.mock(vim.health, true)
    end)

    after_each(function()
        helpers.teardown()
    end)

    local plugin = require("ensure.plugin.mason")

    local opts = {
        packages = { "pkg1", "pkg2", "ignored" },
        ignore = {
            packages = { "ignored" },
            parsers = {},
        },
        plugins = { "ensure.plugin.mason" },
    }

    it("enables itself and installs missing packages on setup", function()
        local registry = require("mason-registry")
        helpers.stub(registry, "is_installed", function(name)
            return name == "pkg2"
        end)

        helpers.stub(plugin, "install_packages")

        plugin:setup(opts)

        assert.is_true(plugin.is_installed)
        assert.is_true(plugin.is_enabled)

        assert.stub(plugin.install_packages).was_called_with(match.is_ref(plugin), { "pkg1" })
    end)

    it("does not enable itself when mason is missing", function()
        helpers.modules_not_found("mason")

        helpers.stub(plugin, "install_packages")

        plugin:setup(opts)

        assert.is_false(plugin.is_installed)
        assert.is_false(plugin.is_enabled)
        assert.stub(plugin.install_packages).was_not_called()
    end)

    it("health reports mason install and version #health", function()
        helpers.stub(plugin, "install_packages")
        package.loaded["mason.version"] = { MAJOR_VERSION = 2 }

        plugin:setup(opts)
        plugin:health()

        assert.stub(vim.health.ok).was_called_with("`Mason` is installed")
        assert.stub(vim.health.ok).was_called_with("`Mason` version is `2.x`")
    end)

    it("health error on wrong version version #health", function()
        helpers.stub(plugin, "install_packages")
        package.loaded["mason.version"] = { MAJOR_VERSION = 1 }

        plugin:setup(opts)
        plugin:health()

        assert.stub(vim.health.ok).was_called_with("`Mason` is installed")
        assert.stub(vim.health.error).was_called_with("`Mason` version is not `2.x`")
    end)

    it("health errors when mason not installed #health", function()
        plugin.is_installed = false

        plugin:health()

        assert.stub(vim.health.error).was_called_with("`Mason` is not installed")
    end)

    it("install_packages skips ignored and empty list", function()
        plugin.is_enabled = true
        plugin.ignore = { "ignored" }

        helpers.stub(plugin, "try_install")

        plugin:install_packages({ "ignored", "pkg1" })
        plugin:install_packages({})

        assert.stub(plugin.try_install).was_called_with(match.is_ref(plugin), "pkg1", match.is_nil())
    end)
end)

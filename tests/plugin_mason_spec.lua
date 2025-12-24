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

    it("health reports mason install and version", function()
        helpers.stub(plugin, "install_packages")
        package.loaded["mason.version"] = { MAJOR_VERSION = 2 }

        plugin:setup(opts)
        plugin:health()

        assert.stub(vim.health.ok).was_called_with("`Mason` is installed")
        assert.stub(vim.health.ok).was_called_with("`Mason` version is `2.x`")
    end)

    it("health error on wrong version version", function()
        helpers.stub(plugin, "install_packages")
        package.loaded["mason.version"] = { MAJOR_VERSION = 1 }

        plugin:setup(opts)
        plugin:health()

        assert.stub(vim.health.ok).was_called_with("`Mason` is installed")
        assert.stub(vim.health.error).was_called_with("`Mason` version is not `2.x`")
    end)

    it("health errors when mason not installed", function()
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

    it("install_packages does nothing when not enabled", function()
        plugin.is_enabled = false
        plugin.ignore = {}

        helpers.stub(plugin, "try_install")

        plugin:install_packages({ "pkg1", "pkg2" })

        assert.stub(plugin.try_install).was_not_called()
    end)

    it("install_packages passes callback to try_install", function()
        plugin.is_enabled = true
        plugin.ignore = {}

        helpers.stub(plugin, "try_install")

        local callback = function() end
        plugin:install_packages({ "pkg1" }, callback)

        assert.stub(plugin.try_install).was_called_with(match.is_ref(plugin), "pkg1", callback)
    end)

    it("autoinstall installs packages for filetype", function()
        local registry = require("mason-registry")
        helpers.stub(registry, "is_installed", false)

        plugin.is_enabled = true
        plugin.packages = { lua = { "stylua", "lua-language-server" } }
        plugin.ignore = {}

        helpers.stub(plugin, "install_packages")

        plugin:autoinstall("lua")

        assert.stub(plugin.install_packages).was_called_with(match.is_ref(plugin), { "stylua", "lua-language-server" })
    end)

    it("autoinstall skips ignored packages", function()
        local registry = require("mason-registry")
        helpers.stub(registry, "is_installed", false)

        plugin.is_enabled = true
        plugin.packages = { lua = { "stylua", "ignored-pkg" } }
        plugin.ignore = { "ignored-pkg" }

        helpers.stub(plugin, "install_packages")

        plugin:autoinstall("lua")

        assert.stub(plugin.install_packages).was_called_with(match.is_ref(plugin), { "stylua" })
    end)

    it("autoinstall does nothing when not enabled", function()
        plugin.is_enabled = false
        plugin.packages = { lua = { "stylua" } }

        helpers.stub(plugin, "install_packages")

        plugin:autoinstall("lua")

        assert.stub(plugin.install_packages).was_not_called()
    end)

    it("autoinstall handles missing filetype packages", function()
        plugin.is_enabled = true
        plugin.packages = {}
        plugin.ignore = {}

        helpers.stub(plugin, "install_packages")

        plugin:autoinstall("unknown")

        assert.stub(plugin.install_packages).was_called_with(match.is_ref(plugin), {})
    end)

    it("install installs all packages including filetype-specific ones", function()
        local registry = require("mason-registry")
        helpers.stub(registry, "is_installed", false)

        plugin.is_enabled = true
        plugin.packages = { "pkg1", "pkg2", lua = { "stylua" } }
        plugin.ignore = {}

        helpers.stub(plugin, "install_packages")

        plugin:install()

        assert.stub(plugin.install_packages).was_called()
    end)

    it("install skips ignored packages", function()
        local registry = require("mason-registry")
        helpers.stub(registry, "is_installed", false)

        plugin.is_enabled = true
        plugin.packages = { "pkg1", "ignored" }
        plugin.ignore = { "ignored" }

        helpers.stub(plugin, "install_packages")

        plugin:install()

        assert.stub(plugin.install_packages).was_called()
    end)

    it("install does nothing when not enabled", function()
        plugin.is_enabled = false
        plugin.packages = { "pkg1" }

        helpers.stub(plugin, "install_packages")

        plugin:install()

        assert.stub(plugin.install_packages).was_not_called()
    end)

    it("resolve returns package when found in registry", function()
        local registry = require("mason-registry")
        local mock_pkg = { name = "stylua" }
        helpers.stub(registry, "get_package", mock_pkg)

        plugin.is_enabled = true

        local result = plugin:resolve("stylua")

        assert.same(mock_pkg, result)
    end)

    it("resolve returns nil when package not found", function()
        local registry = require("mason-registry")
        helpers.stub(registry, "get_package", function()
            error("Package not found")
        end)

        plugin.is_enabled = true

        local result = plugin:resolve("unknown-package")

        assert.is_nil(result)
    end)
end)

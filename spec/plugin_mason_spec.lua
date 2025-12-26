local helpers = require("spec.helpers")
local match = require("luassert.match")

describe("ensure.plugin.mason #plugin #mason", function()
    before_each(function()
        helpers.mock(vim.health, true)
        helpers.stub(vim, "notify")
    end)

    after_each(function()
        helpers.flush_schedule()
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
        helpers.stub(registry, "on")

        helpers.stub(plugin, "install_packages")

        plugin:setup(opts)

        assert.is_true(plugin.is_installed)
        assert.is_true(plugin.is_enabled)

        -- Wait for vim.schedule callbacks to execute
        helpers.flush_schedule()

        assert.stub(plugin.install_packages).was_called_with(match.is_ref(plugin), { "pkg1" })
    end)

    it("registers clear_mappings callback on registry update:success", function()
        local registry = require("mason-registry")
        helpers.stub(registry, "is_installed", false)
        helpers.stub(registry, "on")

        helpers.stub(plugin, "install_packages")

        plugin:setup(opts)

        -- Wait for vim.schedule callbacks to execute
        helpers.flush_schedule()

        assert.stub(registry.on).was_called_with(match.is_ref(registry), "update:success", match.is_function())
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

    describe("try_install", function()
        it("calls callback immediately when package is already installed", function()
            local registry = require("mason-registry")
            helpers.stub(registry, "is_installed", true)

            local Package = require("mason-core.package")
            helpers.stub(Package, "Parse", function(pkg)
                return pkg, nil
            end)

            local callback_called = false
            local callback_pkg = nil
            local callback = function(pkg)
                callback_called = true
                callback_pkg = pkg
            end

            plugin:try_install("lua-language-server", callback)

            assert.is_true(callback_called)
            assert.same("lua-language-server", callback_pkg)
        end)

        it("does not call callback when package is already installed and no callback provided", function()
            local registry = require("mason-registry")
            helpers.stub(registry, "is_installed", true)

            local Package = require("mason-core.package")
            helpers.stub(Package, "Parse", function(pkg)
                return pkg, nil
            end)

            -- Should not error
            plugin:try_install("lua-language-server")
        end)

        it("does not call callback when package is in failed list", function()
            local registry = require("mason-registry")
            helpers.stub(registry, "is_installed", false)

            local Package = require("mason-core.package")
            helpers.stub(Package, "Parse", function(pkg)
                return pkg, nil
            end)

            plugin.failed = { "failed-pkg" }

            local callback_called = false
            local callback = function()
                callback_called = true
            end

            plugin:try_install("failed-pkg", callback)

            assert.is_false(callback_called)
        end)
    end)

    describe("tool mapping", function()
        it("build_mappings_sync returns cached mapping on subsequent calls", function()
            local registry = require("mason-registry")
            helpers.stub(registry, "get_all_package_specs", {
                { name = "stylua", bin = { stylua = "cargo:stylua" } },
            })

            plugin.is_enabled = true
            plugin._tool_to_package = nil
            plugin._lsp_to_mason = nil
            plugin._mason_to_lsp = nil

            plugin:build_mappings_sync()
            plugin:build_mappings_sync()

            assert.stub(registry.get_all_package_specs).was_called(1)
        end)

        it("build_mappings_sync extracts tools from package bin fields", function()
            local registry = require("mason-registry")
            helpers.stub(registry, "get_all_package_specs", {
                { name = "stylua", bin = { stylua = "cargo:stylua" } },
                {
                    name = "cmakelang",
                    bin = { ["cmake-format"] = "pypi:cmakelang", ["cmake-lint"] = "pypi:cmakelang" },
                },
                { name = "no-bin-package" }, -- Package without bin field
            })

            plugin.is_enabled = true
            plugin._tool_to_package = nil
            plugin._lsp_to_mason = nil
            plugin._mason_to_lsp = nil

            plugin:build_mappings_sync()

            assert.same("stylua", plugin._tool_to_package["stylua"])
            assert.same("cmakelang", plugin._tool_to_package["cmake-format"])
            assert.same("cmakelang", plugin._tool_to_package["cmake-lint"])
        end)

        it("build_mappings_sync extracts LSP mappings from neovim.lspconfig fields", function()
            local registry = require("mason-registry")
            helpers.stub(registry, "get_all_package_specs", {
                { name = "lua-language-server", neovim = { lspconfig = "lua_ls" } },
                { name = "pyright", neovim = { lspconfig = "pyright" } },
                { name = "some-tool", neovim = {} },
                { name = "another-tool" },
            })

            plugin.is_enabled = true
            plugin._tool_to_package = nil
            plugin._lsp_to_mason = nil
            plugin._mason_to_lsp = nil

            plugin:build_mappings_sync()

            assert.same("lua-language-server", plugin._lsp_to_mason["lua_ls"])
            assert.same("pyright", plugin._lsp_to_mason["pyright"])
            assert.same("lua_ls", plugin._mason_to_lsp["lua-language-server"])
            assert.same("pyright", plugin._mason_to_lsp["pyright"])
        end)

        it("clear_mappings resets all cached mappings", function()
            plugin._tool_to_package = { stylua = "stylua" }
            plugin._lsp_to_mason = { lua_ls = "lua-language-server" }
            plugin._mason_to_lsp = { ["lua-language-server"] = "lua_ls" }
            plugin._tools_by_filetype = { lua = {} }

            plugin:clear_mappings()

            assert.is_nil(plugin._tool_to_package)
            assert.is_nil(plugin._lsp_to_mason)
            assert.is_nil(plugin._mason_to_lsp)
            assert.is_nil(plugin._tools_by_filetype)
        end)

        it("resolve_tool returns package name for known tool", function()
            plugin.is_enabled = true
            plugin._tool_to_package = { stylua = "stylua", ["cmake-format"] = "cmakelang" }
            plugin._lsp_to_mason = {}
            plugin._mason_to_lsp = {}

            assert.same("stylua", plugin:resolve_tool("stylua"))
            assert.same("cmakelang", plugin:resolve_tool("cmake-format"))
        end)

        it("resolve_tool returns nil for unknown tool", function()
            plugin.is_enabled = true
            plugin._tool_to_package = { stylua = "stylua" }
            plugin._lsp_to_mason = {}
            plugin._mason_to_lsp = {}

            assert.is_nil(plugin:resolve_tool("unknown-tool"))
        end)

        it("resolve_lsp returns package name for known LSP", function()
            plugin.is_enabled = true
            plugin._tool_to_package = {}
            plugin._lsp_to_mason = { lua_ls = "lua-language-server", pyright = "pyright" }
            plugin._mason_to_lsp = {}

            assert.same("lua-language-server", plugin:resolve_lsp("lua_ls"))
            assert.same("pyright", plugin:resolve_lsp("pyright"))
        end)

        it("resolve_lsp returns nil for unknown LSP", function()
            plugin.is_enabled = true
            plugin._tool_to_package = {}
            plugin._lsp_to_mason = { lua_ls = "lua-language-server" }
            plugin._mason_to_lsp = {}

            assert.is_nil(plugin:resolve_lsp("unknown_lsp"))
        end)

        it("lsp_from_package returns LSP name for known package", function()
            plugin.is_enabled = true
            plugin._tool_to_package = {}
            plugin._lsp_to_mason = {}
            plugin._mason_to_lsp = { ["lua-language-server"] = "lua_ls", pyright = "pyright" }

            assert.same("lua_ls", plugin:lsp_from_package("lua-language-server"))
            assert.same("pyright", plugin:lsp_from_package("pyright"))
        end)

        it("lsp_from_package returns nil for unknown package", function()
            plugin.is_enabled = true
            plugin._tool_to_package = {}
            plugin._lsp_to_mason = {}
            plugin._mason_to_lsp = { ["lua-language-server"] = "lua_ls" }

            assert.is_nil(plugin:lsp_from_package("unknown-package"))
        end)

        it("find_lsps_for_filetype returns LSPs with matching filetypes", function()
            plugin.is_enabled = true
            plugin._tool_to_package = {}
            plugin._lsp_to_mason = { lua_ls = "lua-language-server", pyright = "pyright" }
            plugin._mason_to_lsp = {}

            -- Mock vim.lsp.config to return configs via __index (simulating lazy-loading)
            local mock_configs = {
                lua_ls = { filetypes = { "lua" } },
                pyright = { filetypes = { "python" } },
            }
            setmetatable(vim.lsp.config, {
                __index = function(_, key)
                    return mock_configs[key]
                end,
            })

            local results = plugin:find_lsps_for_filetype("lua")

            assert.same(1, #results)
            assert.same("lua_ls", results[1].tool)
            assert.same("lua-language-server", results[1].package)
        end)

        it("find_lsps_for_filetype returns multiple LSPs when available", function()
            plugin.is_enabled = true
            plugin._tool_to_package = {}
            plugin._lsp_to_mason = { pyright = "pyright", pylsp = "python-lsp-server" }
            plugin._mason_to_lsp = {}

            local mock_configs = {
                pyright = { filetypes = { "python" } },
                pylsp = { filetypes = { "python" } },
            }
            setmetatable(vim.lsp.config, {
                __index = function(_, key)
                    return mock_configs[key]
                end,
            })

            local results = plugin:find_lsps_for_filetype("python")

            assert.same(2, #results)
        end)

        it("find_lsps_for_filetype returns empty table when no LSPs match", function()
            plugin.is_enabled = true
            plugin._tool_to_package = {}
            plugin._lsp_to_mason = { lua_ls = "lua-language-server" }
            plugin._mason_to_lsp = {}

            local mock_configs = {
                lua_ls = { filetypes = { "lua" } },
            }
            setmetatable(vim.lsp.config, {
                __index = function(_, key)
                    return mock_configs[key]
                end,
            })

            local results = plugin:find_lsps_for_filetype("python")

            assert.same({}, results)
        end)

        it("find_lsps_for_filetype ignores LSPs without filetypes config", function()
            plugin.is_enabled = true
            plugin._tool_to_package = {}
            plugin._lsp_to_mason = { lua_ls = "lua-language-server", some_lsp = "some-package" }
            plugin._mason_to_lsp = {}

            local mock_configs = {
                lua_ls = { filetypes = { "lua" } },
                some_lsp = {}, -- No filetypes
            }
            setmetatable(vim.lsp.config, {
                __index = function(_, key)
                    return mock_configs[key]
                end,
            })

            local results = plugin:find_lsps_for_filetype("lua")

            assert.same(1, #results)
            assert.same("lua_ls", results[1].tool)
        end)

        it("find_lsps_for_filetype ignores LSPs not in Mason registry", function()
            plugin.is_enabled = true
            plugin._tool_to_package = {}
            plugin._lsp_to_mason = { lua_ls = "lua-language-server" } -- pyright not in mapping
            plugin._mason_to_lsp = {}

            local mock_configs = {
                lua_ls = { filetypes = { "lua" } },
                pyright = { filetypes = { "lua" } }, -- Not in _lsp_to_mason
            }
            setmetatable(vim.lsp.config, {
                __index = function(_, key)
                    return mock_configs[key]
                end,
            })

            local results = plugin:find_lsps_for_filetype("lua")

            assert.same(1, #results)
            assert.same("lua_ls", results[1].tool)
        end)

        it("find_lsps_for_filetype handles LSP config loading errors gracefully", function()
            plugin.is_enabled = true
            plugin._tool_to_package = {}
            plugin._lsp_to_mason = { lua_ls = "lua-language-server", broken_lsp = "broken-package" }
            plugin._mason_to_lsp = {}

            local mock_configs = {
                lua_ls = { filetypes = { "lua" } },
            }
            setmetatable(vim.lsp.config, {
                __index = function(_, key)
                    if key == "broken_lsp" then
                        error("Failed to load LSP config")
                    end
                    return mock_configs[key]
                end,
            })

            local results = plugin:find_lsps_for_filetype("lua")

            -- Should still return lua_ls, gracefully skipping the broken one
            assert.same(1, #results)
            assert.same("lua_ls", results[1].tool)
        end)

        it("build_mappings_sync extracts tools_by_filetype from languages and categories", function()
            local registry = require("mason-registry")
            helpers.stub(registry, "get_all_package_specs", {
                {
                    name = "stylua",
                    bin = { stylua = "cargo:stylua" },
                    languages = { "Lua", "Luau" },
                    categories = { "Formatter" },
                },
                {
                    name = "ruff",
                    bin = { ruff = "pypi:ruff" },
                    languages = { "Python" },
                    categories = { "Linter", "Formatter" },
                },
                {
                    name = "eslint_d",
                    bin = { eslint_d = "npm:eslint_d" },
                    languages = { "JavaScript", "TypeScript" },
                    categories = { "Linter" },
                },
                -- LSP packages should also be included in tools_by_filetype
                {
                    name = "lua-language-server",
                    bin = { ["lua-language-server"] = "cargo:lua-ls" },
                    languages = { "Lua" },
                    categories = { "LSP" },
                    neovim = { lspconfig = "lua_ls" },
                },
            })

            plugin.is_enabled = true
            plugin._tool_to_package = nil
            plugin._lsp_to_mason = nil
            plugin._mason_to_lsp = nil
            plugin._tools_by_filetype = nil

            plugin:build_mappings_sync()

            -- Check tools_by_filetype mapping
            assert.is_not_nil(plugin._tools_by_filetype["lua"])
            assert.same(2, #plugin._tools_by_filetype["lua"]) -- stylua + lua-language-server
            assert.same("stylua", plugin._tools_by_filetype["lua"][1].tool)

            assert.is_not_nil(plugin._tools_by_filetype["luau"])
            assert.same(1, #plugin._tools_by_filetype["luau"])

            assert.is_not_nil(plugin._tools_by_filetype["python"])
            assert.same(1, #plugin._tools_by_filetype["python"])
            assert.same("ruff", plugin._tools_by_filetype["python"][1].tool)
            assert.same({ "Linter", "Formatter" }, plugin._tools_by_filetype["python"][1].categories)

            assert.is_not_nil(plugin._tools_by_filetype["javascript"])
            assert.same(1, #plugin._tools_by_filetype["javascript"])
            assert.same("eslint_d", plugin._tools_by_filetype["javascript"][1].tool)

            assert.is_not_nil(plugin._tools_by_filetype["typescript"])
            assert.same(1, #plugin._tools_by_filetype["typescript"])
        end)

        it("find_formatters_for_filetype returns formatters with matching category", function()
            plugin.is_enabled = true
            plugin._tool_to_package = {}
            plugin._lsp_to_mason = {}
            plugin._mason_to_lsp = {}
            plugin._tools_by_filetype = {
                python = {
                    { tool = "ruff", package = "ruff", categories = { "Linter", "Formatter" } },
                    { tool = "pylint", package = "pylint", categories = { "Linter" } },
                },
            }

            local results = plugin:find_formatters_for_filetype("python")

            assert.same(1, #results)
            assert.same("ruff", results[1].tool)
            assert.same("ruff", results[1].package)
        end)

        it("find_formatters_for_filetype returns multiple formatters", function()
            plugin.is_enabled = true
            plugin._tool_to_package = {}
            plugin._lsp_to_mason = {}
            plugin._mason_to_lsp = {}
            plugin._tools_by_filetype = {
                lua = {
                    { tool = "stylua", package = "stylua", categories = { "Formatter" } },
                    { tool = "luaformatter", package = "luaformatter", categories = { "Formatter" } },
                },
            }

            local results = plugin:find_formatters_for_filetype("lua")

            assert.same(2, #results)
        end)

        it("find_formatters_for_filetype returns empty table for unknown filetype", function()
            plugin.is_enabled = true
            plugin._tool_to_package = {}
            plugin._lsp_to_mason = {}
            plugin._mason_to_lsp = {}
            plugin._tools_by_filetype = {}

            local results = plugin:find_formatters_for_filetype("unknown")

            assert.same({}, results)
        end)

        it("find_linters_for_filetype returns linters with matching category", function()
            plugin.is_enabled = true
            plugin._tool_to_package = {}
            plugin._lsp_to_mason = {}
            plugin._mason_to_lsp = {}
            plugin._tools_by_filetype = {
                python = {
                    { tool = "ruff", package = "ruff", categories = { "Linter", "Formatter" } },
                    { tool = "black", package = "black", categories = { "Formatter" } },
                },
            }

            local results = plugin:find_linters_for_filetype("python")

            assert.same(1, #results)
            assert.same("ruff", results[1].tool)
            assert.same("ruff", results[1].package)
        end)

        it("find_linters_for_filetype returns multiple linters", function()
            plugin.is_enabled = true
            plugin._tool_to_package = {}
            plugin._lsp_to_mason = {}
            plugin._mason_to_lsp = {}
            plugin._tools_by_filetype = {
                javascript = {
                    { tool = "eslint_d", package = "eslint_d", categories = { "Linter" } },
                    { tool = "biome", package = "biome", categories = { "Linter", "Formatter" } },
                },
            }

            local results = plugin:find_linters_for_filetype("javascript")

            assert.same(2, #results)
        end)

        it("find_linters_for_filetype returns empty table for unknown filetype", function()
            plugin.is_enabled = true
            plugin._tool_to_package = {}
            plugin._lsp_to_mason = {}
            plugin._mason_to_lsp = {}
            plugin._tools_by_filetype = {}

            local results = plugin:find_linters_for_filetype("unknown")

            assert.same({}, results)
        end)
    end)
end)

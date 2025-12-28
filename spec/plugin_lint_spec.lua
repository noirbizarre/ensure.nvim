local helpers = require("spec.helpers")
local match = require("luassert.match")

describe("ensure.plugin.lint", function()
    local auto = require("ensure.auto")
    local mason = require("ensure.plugin.mason")
    local plugin = require("ensure.plugin.lint")

    before_each(function()
        helpers.mock(vim.health, true)
        helpers.stub(vim, "notify")
        -- Make vim.defer_fn execute callback immediately for testing
        helpers.stub(vim, "defer_fn", function(fn, _)
            fn()
        end)
        -- Reset all auto-detection state between tests
        auto.reset()
    end)

    after_each(function()
        helpers.teardown()
    end)

    describe("setup", function()
        it("populates lint.linters_by_ft using util.string_list", function()
            local lint = require("lint")
            lint.linters_by_ft = {}

            ---@diagnostic disable-next-line: missing-fields
            plugin:setup({
                linters = {
                    auto = false,
                    lua = "selene",
                    python = { "ruff" },
                },
            })

            assert.is_true(plugin.is_installed)
            assert.same({ "selene" }, lint.linters_by_ft.lua)
            assert.same({ "ruff" }, lint.linters_by_ft.python)
        end)

        it("clears all linters_by_ft when clear=true", function()
            local lint = require("lint")
            lint.linters_by_ft = {
                javascript = { "eslint" },
                typescript = { "eslint" },
            }

            ---@diagnostic disable-next-line: missing-fields
            plugin:setup({
                linters = {
                    auto = false,
                    clear = true,
                    lua = "selene",
                },
            })

            assert.is_true(plugin.is_installed)
            -- Previous linters should be cleared
            assert.is_nil(lint.linters_by_ft.javascript)
            assert.is_nil(lint.linters_by_ft.typescript)
            -- New linters should be set
            assert.same({ "selene" }, lint.linters_by_ft.lua)
        end)

        it("does not clear linters_by_ft when clear=false", function()
            local lint = require("lint")
            lint.linters_by_ft = {
                javascript = { "eslint" },
            }

            ---@diagnostic disable-next-line: missing-fields
            plugin:setup({
                linters = {
                    auto = false,
                    clear = false,
                    lua = "selene",
                },
            })

            assert.is_true(plugin.is_installed)
            -- Previous linters should be preserved
            assert.same({ "eslint" }, lint.linters_by_ft.javascript)
            -- New linters should be set
            assert.same({ "selene" }, lint.linters_by_ft.lua)
        end)

        it("does nothing when lint is not installed", function()
            local lint = require("lint")
            lint.linters_by_ft = {}

            helpers.modules_not_found("lint")

            ---@diagnostic disable-next-line: missing-fields
            plugin:setup({
                linters = {
                    auto = false,
                    lua = "selene",
                },
            })

            assert.is_false(plugin.is_installed)
            assert.is.same(lint.linters_by_ft, {})
        end)

        it("normalizes boolean auto=true to table with defaults", function()
            local lint = require("lint")
            lint.linters_by_ft = {}

            ---@diagnostic disable-next-line: missing-fields
            plugin:setup({
                linters = {
                    auto = true,
                },
            })

            assert.is_table(plugin.auto.config)
            assert.is_true(plugin.auto.config.enable)
            assert.same({
                "alex",
                "codespell",
                "cspell",
                "misspell",
                "proselint",
                "textlint",
                "typos",
                "vale",
                "woke",
                "write_good",
            }, plugin.auto.config.ignore)
            assert.is_true(plugin.auto.config.multi)
        end)

        it("normalizes boolean auto=false to table with defaults", function()
            local lint = require("lint")
            lint.linters_by_ft = {}

            ---@diagnostic disable-next-line: missing-fields
            plugin:setup({
                linters = {
                    auto = false,
                },
            })

            assert.is_table(plugin.auto.config)
            assert.is_false(plugin.auto.config.enable)
            assert.same({
                "alex",
                "codespell",
                "cspell",
                "misspell",
                "proselint",
                "textlint",
                "typos",
                "vale",
                "woke",
                "write_good",
            }, plugin.auto.config.ignore)
            assert.is_true(plugin.auto.config.multi)
        end)

        it("merges auto table config with defaults", function()
            local lint = require("lint")
            lint.linters_by_ft = {}

            ---@diagnostic disable-next-line: missing-fields
            plugin:setup({
                linters = {
                    auto = {
                        enable = true,
                        ignore = { "pylint" },
                    },
                },
            })

            assert.is_table(plugin.auto.config)
            assert.is_true(plugin.auto.config.enable)
            -- User ignore list is merged with defaults
            assert.same({
                "alex",
                "codespell",
                "cspell",
                "misspell",
                "proselint",
                "textlint",
                "typos",
                "vale",
                "woke",
                "write_good",
                "pylint",
            }, plugin.auto.config.ignore)
            assert.is_true(plugin.auto.config.multi) -- default
        end)

        it("allows disabling multi in auto config", function()
            local lint = require("lint")
            lint.linters_by_ft = {}

            ---@diagnostic disable-next-line: missing-fields
            plugin:setup({
                linters = {
                    auto = {
                        enable = true,
                        multi = false,
                    },
                },
            })

            assert.is_table(plugin.auto.config)
            assert.is_true(plugin.auto.config.enable)
            assert.is_false(plugin.auto.config.multi)
        end)

        it("does not register 'auto' as a filetype", function()
            local lint = require("lint")
            lint.linters_by_ft = {}

            ---@diagnostic disable-next-line: missing-fields
            plugin:setup({
                linters = {
                    auto = true,
                    lua = "selene",
                },
            })

            assert.is_nil(lint.linters_by_ft.auto)
            assert.same({ "selene" }, lint.linters_by_ft.lua)
        end)
    end)

    describe("health", function()
        it("reports install state and mason plugin enabled/disabled", function()
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

        it("errors when nvim-lint not installed", function()
            plugin.is_installed = false
            mason.is_enabled = true

            plugin:health()

            assert.stub(vim.health.error).was_called_with("`nvim-lint` is not installed")
        end)
    end)

    describe("autoinstall", function()
        it("resolves linters to mason packages and installs them", function()
            local lint = require("lint")
            lint.linters_by_ft = { lua = { "mh_lint", "other" } }

            mason.is_enabled = true
            plugin.is_installed = true
            plugin.auto.config = { enable = false, ignore = {}, multi = true }
            helpers.stub(mason, "install_packages")

            -- Mock resolve_package to return expected mappings
            helpers.stub(plugin, "resolve_package", function(_, linter_name)
                local mapping = { mh_lint = "miss_hit", other = "other" }
                return mapping[linter_name]
            end)

            plugin:autoinstall("lua")

            assert.stub(mason.install_packages).was_called_with(match.is_ref(mason), { "miss_hit", "other" })
        end)

        it("does nothing when lint not installed", function()
            plugin.is_installed = false
            mason.is_enabled = true
            plugin.auto.config = { enable = false, ignore = {}, multi = true }
            helpers.stub(mason, "install_packages")

            plugin:autoinstall("lua")

            assert.stub(mason.install_packages).was_not_called()
        end)

        it("does nothing when mason not enabled", function()
            plugin.is_installed = true
            mason.is_enabled = false
            plugin.auto.config = { enable = false, ignore = {}, multi = true }
            helpers.stub(mason, "install_packages")

            plugin:autoinstall("lua")

            assert.stub(mason.install_packages).was_not_called()
        end)
    end)

    describe("linters.auto feature", function()
        it("does not run auto-detection when auto.enable is false", function()
            local lint = require("lint")
            lint.linters_by_ft = {}
            helpers.stub(lint, "_resolve_linter_by_ft", {})

            mason.is_enabled = true
            plugin.is_installed = true
            plugin.auto.config = { enable = false, ignore = {}, multi = true }
            helpers.stub(mason, "install_packages")
            helpers.stub(mason, "find_linters_for_filetype")

            plugin:autoinstall("lua")

            assert.stub(mason.find_linters_for_filetype).was_not_called()
        end)

        it("does not run auto-detection when a linter is already configured for the filetype", function()
            local lint = require("lint")
            lint.linters_by_ft = { lua = { "selene" } }
            helpers.stub(lint, "_resolve_linter_by_ft", { "selene" })

            mason.is_enabled = true
            plugin.is_installed = true
            plugin.auto.config = { enable = true, ignore = {}, multi = true }
            helpers.stub(mason, "install_packages")
            helpers.stub(mason, "find_linters_for_filetype")
            helpers.stub(plugin, "resolve_package", nil)

            plugin:autoinstall("lua")

            assert.stub(mason.find_linters_for_filetype).was_not_called()
        end)

        it("runs auto-detection when auto.enable is true and no linter is configured", function()
            local lint = require("lint")
            lint.linters_by_ft = {}
            helpers.stub(lint, "_resolve_linter_by_ft", {})

            mason.is_enabled = true
            plugin.is_installed = true
            plugin.auto.config = { enable = true, ignore = {}, multi = true }
            helpers.stub(mason, "install_packages")
            helpers.stub(mason, "find_linters_for_filetype", {})

            plugin:autoinstall("lua")

            assert.stub(mason.find_linters_for_filetype).was_called_with(match.is_ref(mason), "lua")
        end)

        it("auto-enables single linter when only one is available", function()
            local lint = require("lint")
            lint.linters_by_ft = {}
            helpers.stub(lint, "_resolve_linter_by_ft", {})

            mason.is_enabled = true
            plugin.is_installed = true
            plugin.auto.config = { enable = true, ignore = {}, multi = true }
            helpers.stub(mason, "install_packages")
            helpers.stub(mason, "find_linters_for_filetype", {
                { tool = "selene", package = "selene" },
            })
            helpers.stub(plugin.auto, "enable")

            plugin:autoinstall("lua")

            assert
                .stub(plugin.auto.enable)
                .was_called_with(match.is_ref(plugin.auto), { tool = "selene", package = "selene" }, "lua")
        end)

        it("prompts user selection when multiple linters are available and multi is true", function()
            local lint = require("lint")
            lint.linters_by_ft = {}
            helpers.stub(lint, "_resolve_linter_by_ft", {})

            mason.is_enabled = true
            plugin.is_installed = true
            plugin.auto.config = { enable = true, ignore = {}, multi = true }
            helpers.stub(mason, "install_packages")
            helpers.stub(mason, "find_linters_for_filetype", {
                { tool = "pylint", package = "pylint" },
                { tool = "ruff", package = "ruff" },
            })
            -- Stub _detector.prompt_selection to verify it's called with correct args
            helpers.stub(plugin.auto, "prompt_selection")

            plugin:autoinstall("python")

            assert.stub(plugin.auto.prompt_selection).was_called_with(match.is_ref(plugin.auto), {
                { tool = "pylint", package = "pylint" },
                { tool = "ruff", package = "ruff" },
            }, "python")
        end)

        it("does nothing when multiple linters are available and multi is false", function()
            local lint = require("lint")
            lint.linters_by_ft = {}
            helpers.stub(lint, "_resolve_linter_by_ft", {})

            mason.is_enabled = true
            plugin.is_installed = true
            plugin.auto.config = { enable = true, ignore = {}, multi = false }
            helpers.stub(mason, "install_packages")
            helpers.stub(mason, "find_linters_for_filetype", {
                { tool = "pylint", package = "pylint" },
                { tool = "ruff", package = "ruff" },
            })
            helpers.stub(plugin.auto, "enable")
            helpers.stub(plugin.auto, "prompt_selection")

            plugin:autoinstall("python")

            assert.stub(plugin.auto.enable).was_not_called()
            assert.stub(plugin.auto.prompt_selection).was_not_called()
        end)

        it("filters ignored linters from auto-detection results", function()
            local lint = require("lint")
            lint.linters_by_ft = {}
            helpers.stub(lint, "_resolve_linter_by_ft", {})

            mason.is_enabled = true
            plugin.is_installed = true
            plugin.auto.config = { enable = true, ignore = { "pylint" }, multi = true }
            helpers.stub(mason, "install_packages")
            helpers.stub(mason, "find_linters_for_filetype", {
                { tool = "ruff", package = "ruff" },
                { tool = "pylint", package = "pylint" },
            })
            helpers.stub(plugin.auto, "enable")

            plugin:autoinstall("python")

            -- Should only auto-enable ruff, ignoring pylint
            assert
                .stub(plugin.auto.enable)
                .was_called_with(match.is_ref(plugin.auto), { tool = "ruff", package = "ruff" }, "python")
        end)

        it("does nothing when all available linters are ignored", function()
            local lint = require("lint")
            lint.linters_by_ft = {}
            helpers.stub(lint, "_resolve_linter_by_ft", {})

            mason.is_enabled = true
            plugin.is_installed = true
            plugin.auto.config = { enable = true, ignore = { "pylint", "ruff" }, multi = true }
            helpers.stub(mason, "install_packages")
            helpers.stub(mason, "find_linters_for_filetype", {
                { tool = "pylint", package = "pylint" },
                { tool = "ruff", package = "ruff" },
            })
            helpers.stub(plugin.auto, "enable")
            helpers.stub(plugin.auto, "prompt_selection")

            plugin:autoinstall("python")

            assert.stub(plugin.auto.enable).was_not_called()
            assert.stub(plugin.auto.prompt_selection).was_not_called()
        end)
    end)

    -- Note: auto_enable_linter tests removed - functionality moved to ensure.auto module
    -- and tested in spec/auto_spec.lua

    describe("dump_session", function()
        it("does nothing when no Linter choices exist", function()
            local choices = {}
            local lines = {}

            plugin:dump_session(choices, lines)

            assert.same({}, lines)
        end)

        it("does nothing when Linter choices is empty", function()
            local choices = { ["Linter"] = {} }
            local lines = {}

            plugin:dump_session(choices, lines)

            assert.same({}, lines)
        end)

        it("generates linters config for single filetype", function()
            local choices = {
                ["Linter"] = {
                    lua = { tool = "selene", package = "selene" },
                },
            }
            local lines = {}

            plugin:dump_session(choices, lines)

            assert.same({
                "linters = {",
                '    lua = "selene",',
                "},",
            }, lines)
        end)

        it("generates sorted linters config for multiple filetypes", function()
            local choices = {
                ["Linter"] = {
                    python = { tool = "ruff", package = "ruff" },
                    lua = { tool = "selene", package = "selene" },
                    javascript = { tool = "eslint", package = "eslint_d" },
                },
            }
            local lines = {}

            plugin:dump_session(choices, lines)

            assert.same({
                "linters = {",
                '    javascript = "eslint",',
                '    lua = "selene",',
                '    python = "ruff",',
                "},",
            }, lines)
        end)

        it("ignores other choice kinds", function()
            local choices = {
                ["LSP server"] = { lua = { tool = "lua_ls", package = "lua-language-server" } },
                ["Formatter"] = { lua = { tool = "stylua", package = "stylua" } },
            }
            local lines = {}

            plugin:dump_session(choices, lines)

            assert.same({}, lines)
        end)

        it("appends to existing lines", function()
            local choices = {
                ["Linter"] = {
                    lua = { tool = "selene", package = "selene" },
                },
            }
            local lines = { "-- existing line" }

            plugin:dump_session(choices, lines)

            assert.same({
                "-- existing line",
                "linters = {",
                '    lua = "selene",',
                "},",
            }, lines)
        end)
    end)

    describe("install", function()
        it("installs all configured linters via mason", function()
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
                .was_called_with(match.is_ref(mason), match.table_with({ "miss_hit", "buf", "foo" }))
        end)

        it("does nothing when lint not installed", function()
            plugin.is_installed = false
            mason.is_enabled = true
            helpers.stub(mason, "install_packages")

            plugin:install()

            assert.stub(mason.install_packages).was_not_called()
        end)

        it("does nothing when mason not enabled", function()
            local lint = require("lint")
            lint.linters_by_ft = { lua = { "selene" } }

            plugin.is_installed = true
            mason.is_enabled = false
            helpers.stub(mason, "install_packages")

            plugin:install()

            assert.stub(mason.install_packages).was_not_called()
        end)
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
            assert.stub(mason.resolve_tool).was_called_with(match.is_ref(mason), "selene")
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
            assert.stub(mason.resolve_tool).was_called_with(match.is_ref(mason), "factory-cmd")
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
            assert.stub(mason.resolve_tool).was_called_with(match.is_ref(mason), "dynamic-executable")
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

            assert.stub(mason.resolve_tool).was_called_with(match.is_ref(mason), "my-linter")
        end)
    end)
end)

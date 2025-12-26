local helpers = require("spec.helpers")
local match = require("luassert.match")

describe("ensure.plugin.conform", function()
    local mason = require("ensure.plugin.mason")
    local plugin = require("ensure.plugin.conform")

    before_each(function()
        helpers.mock(vim.health, true)
        helpers.stub(vim, "notify")
        -- Make vim.defer_fn execute callback immediately for testing
        helpers.stub(vim, "defer_fn", function(fn, _)
            fn()
        end)
        -- Reset prompt queue state between tests
        plugin:clear_prompt_queue()
    end)

    after_each(function()
        helpers.teardown()
    end)

    describe("setup", function()
        it("does nothing when conform is not installed", function()
            helpers.modules_not_found("conform")

            ---@diagnostic disable-next-line: missing-fields
            plugin:setup({ formatters = { auto = false, lua = { "stylua" } } })

            assert.is_false(plugin.is_installed)
        end)

        it("registers formatters by filetype using util.string_list", function()
            local conform = require("conform")
            conform.formatters_by_ft = {}

            ---@diagnostic disable-next-line: missing-fields
            plugin:setup({
                formatters = {
                    auto = false,
                    lua = "stylua",
                    python = { "ruff_format" },
                },
            })

            assert.is_true(plugin.is_installed)
            assert.same({ "stylua" }, conform.formatters_by_ft.lua)
            assert.same({ "ruff_format" }, conform.formatters_by_ft.python)
        end)

        it("normalizes boolean auto=true to table with defaults", function()
            local conform = require("conform")
            conform.formatters_by_ft = {}

            ---@diagnostic disable-next-line: missing-fields
            plugin:setup({
                formatters = {
                    auto = true,
                },
            })

            assert.is_table(plugin.auto)
            assert.is_true(plugin.auto.enable)
            assert.same({}, plugin.auto.ignore)
            assert.is_true(plugin.auto.multi)
        end)

        it("normalizes boolean auto=false to table with defaults", function()
            local conform = require("conform")
            conform.formatters_by_ft = {}

            ---@diagnostic disable-next-line: missing-fields
            plugin:setup({
                formatters = {
                    auto = false,
                },
            })

            assert.is_table(plugin.auto)
            assert.is_false(plugin.auto.enable)
            assert.same({}, plugin.auto.ignore)
            assert.is_true(plugin.auto.multi)
        end)

        it("merges auto table config with defaults", function()
            local conform = require("conform")
            conform.formatters_by_ft = {}

            ---@diagnostic disable-next-line: missing-fields
            plugin:setup({
                formatters = {
                    auto = {
                        enable = true,
                        ignore = { "prettier" },
                    },
                },
            })

            assert.is_table(plugin.auto)
            assert.is_true(plugin.auto.enable)
            assert.same({ "prettier" }, plugin.auto.ignore)
            assert.is_true(plugin.auto.multi) -- default
        end)

        it("allows disabling multi in auto config", function()
            local conform = require("conform")
            conform.formatters_by_ft = {}

            ---@diagnostic disable-next-line: missing-fields
            plugin:setup({
                formatters = {
                    auto = {
                        enable = true,
                        multi = false,
                    },
                },
            })

            assert.is_table(plugin.auto)
            assert.is_true(plugin.auto.enable)
            assert.is_false(plugin.auto.multi)
        end)

        it("does not register 'auto' as a filetype", function()
            local conform = require("conform")
            conform.formatters_by_ft = {}

            ---@diagnostic disable-next-line: missing-fields
            plugin:setup({
                formatters = {
                    auto = true,
                    lua = "stylua",
                },
            })

            assert.is_nil(conform.formatters_by_ft.auto)
            assert.same({ "stylua" }, conform.formatters_by_ft.lua)
        end)
    end)

    describe("autoinstall", function()
        it("resolves formatters to mason packages and calls install_packages", function()
            local conform = require("conform")
            helpers.stub(conform, "list_formatters_for_buffer", { "ruff_fix", "prettier" })

            mason.is_enabled = true
            plugin.auto = { enable = false, ignore = {}, multi = true }
            helpers.stub(mason, "install_packages")
            plugin.is_installed = true

            helpers.stub(vim.api, "nvim_get_current_buf", 1)

            -- Mock resolve_package to return expected mappings
            helpers.stub(plugin, "resolve_package", function(_, formatter_name)
                local mapping = { ruff_fix = "ruff", prettier = "prettier" }
                return mapping[formatter_name]
            end)

            plugin:autoinstall("lua")

            assert.stub(mason.install_packages).was_called_with(match.is_ref(mason), { "ruff", "prettier" })
        end)
    end)

    describe("health", function()
        it("reports conform installed and mason enabled", function()
            plugin.is_installed = true
            mason.is_enabled = true

            plugin:health()

            assert.stub(vim.health.ok).was_called_with("`conform.nvim` is installed")
            assert.stub(vim.health.ok).was_called_with("`ensure.plugin.mason` plugin is enabled")
        end)

        it("errors when conform not installed", function()
            plugin.is_installed = false
            mason.is_enabled = true

            plugin:health()

            assert.stub(vim.health.error).was_called_with("`conform.nvim` is not installed")
        end)

        it("warns when mason plugin not enabled", function()
            plugin.is_installed = true
            mason.is_enabled = false

            plugin:health()

            assert.stub(vim.health.ok).was_called_with("`conform.nvim` is installed")
            assert
                .stub(vim.health.warn)
                .was_called_with("`ensure.plugin.mason` plugin is not enabled, formatters won't be installed")
        end)
    end)

    describe("formatters.auto feature", function()
        it("does not run auto-detection when auto.enable is false", function()
            local conform = require("conform")
            conform.formatters_by_ft = {}
            helpers.stub(conform, "list_formatters_for_buffer", {})

            mason.is_enabled = true
            plugin.is_installed = true
            plugin.auto = { enable = false, ignore = {}, multi = true }
            helpers.stub(mason, "install_packages")
            helpers.stub(mason, "find_formatters_for_filetype")
            helpers.stub(vim.api, "nvim_get_current_buf", 1)

            plugin:autoinstall("lua")

            assert.stub(mason.find_formatters_for_filetype).was_not_called()
        end)

        it("does not run auto-detection when a formatter is already configured for the filetype", function()
            local conform = require("conform")
            conform.formatters_by_ft = {}
            helpers.stub(conform, "list_formatters_for_buffer", { "stylua" })

            mason.is_enabled = true
            plugin.is_installed = true
            plugin.auto = { enable = true, ignore = {}, multi = true }
            helpers.stub(mason, "install_packages")
            helpers.stub(mason, "find_formatters_for_filetype")
            helpers.stub(plugin, "resolve_package", nil)
            helpers.stub(vim.api, "nvim_get_current_buf", 1)

            plugin:autoinstall("lua")

            assert.stub(mason.find_formatters_for_filetype).was_not_called()
        end)

        it("runs auto-detection when auto.enable is true and no formatter is configured", function()
            local conform = require("conform")
            conform.formatters_by_ft = {}
            helpers.stub(conform, "list_formatters_for_buffer", {})

            mason.is_enabled = true
            plugin.is_installed = true
            plugin.auto = { enable = true, ignore = {}, multi = true }
            helpers.stub(mason, "install_packages")
            helpers.stub(mason, "find_formatters_for_filetype", {})
            helpers.stub(vim.api, "nvim_get_current_buf", 1)

            plugin:autoinstall("lua")

            assert.stub(mason.find_formatters_for_filetype).was_called_with(match.is_ref(mason), "lua")
        end)

        it("auto-enables single formatter when only one is available", function()
            local conform = require("conform")
            conform.formatters_by_ft = {}
            helpers.stub(conform, "list_formatters_for_buffer", {})

            mason.is_enabled = true
            plugin.is_installed = true
            plugin.auto = { enable = true, ignore = {}, multi = true }
            helpers.stub(mason, "install_packages")
            helpers.stub(mason, "find_formatters_for_filetype", {
                { tool = "stylua", package = "stylua" },
            })
            helpers.stub(plugin, "auto_enable_formatter")
            helpers.stub(vim.api, "nvim_get_current_buf", 1)

            plugin:autoinstall("lua")

            assert
                .stub(plugin.auto_enable_formatter)
                .was_called_with(match.is_ref(plugin), { tool = "stylua", package = "stylua" }, "lua")
        end)

        it("prompts user selection when multiple formatters are available and multi is true", function()
            local conform = require("conform")
            conform.formatters_by_ft = {}
            helpers.stub(conform, "list_formatters_for_buffer", {})

            mason.is_enabled = true
            plugin.is_installed = true
            plugin.auto = { enable = true, ignore = {}, multi = true }
            helpers.stub(mason, "install_packages")
            helpers.stub(mason, "find_formatters_for_filetype", {
                { tool = "black", package = "black" },
                { tool = "ruff", package = "ruff" },
            })
            helpers.stub(plugin, "prompt_formatter_selection")
            helpers.stub(vim.api, "nvim_get_current_buf", 1)

            plugin:autoinstall("python")

            assert.stub(plugin.prompt_formatter_selection).was_called_with(match.is_ref(plugin), {
                { tool = "black", package = "black" },
                { tool = "ruff", package = "ruff" },
            }, "python")
        end)

        it("does nothing when multiple formatters are available and multi is false", function()
            local conform = require("conform")
            conform.formatters_by_ft = {}
            helpers.stub(conform, "list_formatters_for_buffer", {})

            mason.is_enabled = true
            plugin.is_installed = true
            plugin.auto = { enable = true, ignore = {}, multi = false }
            helpers.stub(mason, "install_packages")
            helpers.stub(mason, "find_formatters_for_filetype", {
                { tool = "black", package = "black" },
                { tool = "ruff", package = "ruff" },
            })
            helpers.stub(plugin, "auto_enable_formatter")
            helpers.stub(plugin, "prompt_formatter_selection")
            helpers.stub(vim.api, "nvim_get_current_buf", 1)

            plugin:autoinstall("python")

            assert.stub(plugin.auto_enable_formatter).was_not_called()
            assert.stub(plugin.prompt_formatter_selection).was_not_called()
        end)

        it("filters ignored formatters from auto-detection results", function()
            local conform = require("conform")
            conform.formatters_by_ft = {}
            helpers.stub(conform, "list_formatters_for_buffer", {})

            mason.is_enabled = true
            plugin.is_installed = true
            plugin.auto = { enable = true, ignore = { "prettier" }, multi = true }
            helpers.stub(mason, "install_packages")
            helpers.stub(mason, "find_formatters_for_filetype", {
                { tool = "biome", package = "biome" },
                { tool = "prettier", package = "prettier" },
            })
            helpers.stub(plugin, "auto_enable_formatter")
            helpers.stub(vim.api, "nvim_get_current_buf", 1)

            plugin:autoinstall("javascript")

            -- Should only auto-enable biome, ignoring prettier
            assert
                .stub(plugin.auto_enable_formatter)
                .was_called_with(match.is_ref(plugin), { tool = "biome", package = "biome" }, "javascript")
        end)

        it("does nothing when all available formatters are ignored", function()
            local conform = require("conform")
            conform.formatters_by_ft = {}
            helpers.stub(conform, "list_formatters_for_buffer", {})

            mason.is_enabled = true
            plugin.is_installed = true
            plugin.auto = { enable = true, ignore = { "prettier", "biome" }, multi = true }
            helpers.stub(mason, "install_packages")
            helpers.stub(mason, "find_formatters_for_filetype", {
                { tool = "prettier", package = "prettier" },
                { tool = "biome", package = "biome" },
            })
            helpers.stub(plugin, "auto_enable_formatter")
            helpers.stub(plugin, "prompt_formatter_selection")
            helpers.stub(vim.api, "nvim_get_current_buf", 1)

            plugin:autoinstall("javascript")

            assert.stub(plugin.auto_enable_formatter).was_not_called()
            assert.stub(plugin.prompt_formatter_selection).was_not_called()
        end)
    end)

    describe("auto_enable_formatter", function()
        it("installs package and enables formatter on success", function()
            local conform = require("conform")
            conform.formatters_by_ft = {}

            helpers.stub(mason, "try_install", function(_, _, callback)
                callback()
            end)

            plugin:auto_enable_formatter({ tool = "stylua", package = "stylua" }, "lua")

            assert.stub(mason.try_install).was_called_with(match.is_ref(mason), "stylua", match.is_function())
            assert.same({ "stylua" }, conform.formatters_by_ft.lua)
        end)
    end)

    describe("prompt_formatter_selection", function()
        -- Helper to call prompt_formatter_selection inside a coroutine (as the function requires)
        local function call_in_coroutine(fn)
            local coro = coroutine.create(fn)
            coroutine.resume(coro)
            return coro
        end

        it("calls vim.ui.select with formatter options and format_item", function()
            -- Stub vim.schedule to execute immediately
            helpers.stub(vim, "schedule", function(fn)
                fn()
            end)

            local captured_items, captured_opts
            helpers.stub(vim.ui, "select", function(items, opts, _)
                captured_items = items
                captured_opts = opts
            end)

            local available = {
                { tool = "black", package = "black" },
                { tool = "ruff", package = "ruff" },
            }

            call_in_coroutine(function()
                plugin:prompt_formatter_selection(available, "python")
            end)

            assert.stub(vim.ui.select).was_called()
            assert.equals(2, #captured_items)
            assert.equals("black", captured_items[1].tool)
            assert.equals("ruff", captured_items[2].tool)
            assert.matches("python", captured_opts.prompt)
            -- Test format_item returns tool name
            assert.equals("black", captured_opts.format_item(captured_items[1]))
        end)

        it("auto-enables selected formatter when user makes a choice", function()
            -- Stub vim.schedule to execute immediately
            helpers.stub(vim, "schedule", function(fn)
                fn()
            end)

            local select_callback
            helpers.stub(vim.ui, "select", function(_, _, callback)
                select_callback = callback
            end)
            helpers.stub(plugin, "auto_enable_formatter")

            local available = {
                { tool = "black", package = "black" },
                { tool = "ruff", package = "ruff" },
            }
            local ruff_entry = available[2]

            local coro = call_in_coroutine(function()
                plugin:prompt_formatter_selection(available, "python")
            end)

            -- Simulate user selecting ruff entry
            select_callback(ruff_entry)

            -- Wait for coroutine to complete
            assert.equals("dead", coroutine.status(coro))

            assert.stub(plugin.auto_enable_formatter).was_called_with(match.is_ref(plugin), ruff_entry, "python")
        end)

        it("does nothing when user cancels selection", function()
            -- Stub vim.schedule to execute immediately
            helpers.stub(vim, "schedule", function(fn)
                fn()
            end)

            local select_callback
            helpers.stub(vim.ui, "select", function(_, _, callback)
                select_callback = callback
            end)
            helpers.stub(plugin, "auto_enable_formatter")

            local available = {
                { tool = "black", package = "black" },
            }

            local coro = call_in_coroutine(function()
                plugin:prompt_formatter_selection(available, "python")
            end)

            -- Simulate user canceling (nil choice)
            select_callback(nil)

            -- Wait for coroutine to complete
            assert.equals("dead", coroutine.status(coro))

            assert.stub(plugin.auto_enable_formatter).was_not_called()
        end)
    end)

    describe("install", function()
        it("installs all known formatters via mason", function()
            local conform = require("conform")
            conform.formatters_by_ft = {
                lua = { "stylua" },
                python = { "ruff_format" },
                unknown = { "unknown_formatter" },
            }

            mason.is_enabled = true
            helpers.stub(mason, "install_packages")
            plugin.is_installed = true

            -- Mock resolve_package to return expected mappings (nil for unknown)
            helpers.stub(plugin, "resolve_package", function(_, formatter_name)
                local mapping = { stylua = "stylua", ruff_format = "ruff" }
                return mapping[formatter_name]
            end)

            plugin:install()

            assert.stub(mason.install_packages).was_called_with(
                match.is_ref(mason),
                match.is_all_of(match.table_with({ "stylua", "ruff" }), match.table_without({ "unknown_formatter" }))
            )
        end)

        it("does nothing when mason not enabled", function()
            mason.is_enabled = false
            helpers.stub(mason, "install_packages")
            plugin.is_installed = true

            plugin:install()

            assert.stub(mason.install_packages).was_not_called()
        end)

        it("does nothing when conform not installed", function()
            mason.is_enabled = true
            helpers.stub(mason, "install_packages")
            plugin.is_installed = false

            plugin:install()

            assert.stub(mason.install_packages).was_not_called()
        end)
    end)

    describe("resolve_package", function()
        it("returns nil when formatter is already available", function()
            local conform = require("conform")
            helpers.stub(conform, "get_formatter_info", {
                name = "stylua",
                command = "stylua",
                available = true,
            })

            mason.is_enabled = true
            helpers.stub(mason, "resolve_tool", "stylua")

            local result = plugin:resolve_package("stylua")

            assert.is_nil(result)
            assert.stub(mason.resolve_tool).was_not_called()
        end)

        it("returns package name when formatter is not available", function()
            local conform = require("conform")
            helpers.stub(conform, "get_formatter_info", {
                name = "stylua",
                command = "stylua",
                available = false,
            })

            mason.is_enabled = true
            helpers.stub(mason, "resolve_tool", "stylua")

            local result = plugin:resolve_package("stylua")

            assert.same("stylua", result)
            assert.stub(mason.resolve_tool).was_called_with(match.is_ref(mason), "stylua")
        end)

        it("returns nil when mason is not enabled", function()
            mason.is_enabled = false

            local result = plugin:resolve_package("stylua")

            assert.is_nil(result)
        end)

        it("returns nil when formatter info has no command", function()
            local conform = require("conform")
            helpers.stub(conform, "get_formatter_info", {
                name = "unknown",
                available = false,
            })

            mason.is_enabled = true

            local result = plugin:resolve_package("unknown")

            assert.is_nil(result)
        end)

        it("extracts executable name from full path", function()
            local conform = require("conform")
            helpers.stub(conform, "get_formatter_info", {
                name = "stylua",
                command = "/home/user/.local/share/nvim/mason/bin/stylua",
                available = false,
            })

            mason.is_enabled = true
            helpers.stub(mason, "resolve_tool", "stylua")

            plugin:resolve_package("stylua")

            assert.stub(mason.resolve_tool).was_called_with(match.is_ref(mason), "stylua")
        end)
    end)
end)

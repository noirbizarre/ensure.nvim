local helpers = require("spec.helpers")
local match = require("luassert.match")

describe("ensure.plugin.lsp", function()
    local mason = require("ensure.plugin.mason")
    local plugin = require("ensure.plugin.lsp")

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

        it("normalizes boolean auto=true to table with defaults", function()
            helpers.stub(vim.lsp, "enable")
            helpers.stub(vim.lsp, "config")

            ---@diagnostic disable-next-line: missing-fields
            plugin:setup({
                lsp = {
                    enable = {},
                    disable = {},
                    auto = true,
                },
            })

            assert.is_table(plugin.auto)
            assert.is_true(plugin.auto.enable)
            assert.same({ "copilot", "ltex", "ltex_plus" }, plugin.auto.ignore)
            assert.is_true(plugin.auto.multi)
        end)

        it("normalizes boolean auto=false to table with defaults", function()
            helpers.stub(vim.lsp, "enable")
            helpers.stub(vim.lsp, "config")

            ---@diagnostic disable-next-line: missing-fields
            plugin:setup({
                lsp = {
                    enable = {},
                    disable = {},
                    auto = false,
                },
            })

            assert.is_table(plugin.auto)
            assert.is_false(plugin.auto.enable)
            assert.same({ "copilot", "ltex", "ltex_plus" }, plugin.auto.ignore)
            assert.is_true(plugin.auto.multi)
        end)

        it("defaults auto to disabled table when not specified", function()
            helpers.stub(vim.lsp, "enable")
            helpers.stub(vim.lsp, "config")

            ---@diagnostic disable-next-line: missing-fields
            plugin:setup({
                lsp = {
                    enable = {},
                    disable = {},
                },
            })

            assert.is_table(plugin.auto)
            assert.is_false(plugin.auto.enable)
        end)

        it("merges auto table config with defaults", function()
            helpers.stub(vim.lsp, "enable")
            helpers.stub(vim.lsp, "config")

            ---@diagnostic disable-next-line: missing-fields
            plugin:setup({
                lsp = {
                    enable = {},
                    disable = {},
                    auto = {
                        enable = true,
                        ignore = { "custom_lsp" },
                    },
                },
            })

            assert.is_table(plugin.auto)
            assert.is_true(plugin.auto.enable)
            assert.same({ "custom_lsp" }, plugin.auto.ignore)
            assert.is_true(plugin.auto.multi) -- default
        end)

        it("allows disabling multi in auto config", function()
            helpers.stub(vim.lsp, "enable")
            helpers.stub(vim.lsp, "config")

            ---@diagnostic disable-next-line: missing-fields
            plugin:setup({
                lsp = {
                    enable = {},
                    disable = {},
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
    end)

    describe("health", function()
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

        it("health errors when mason plugin is not enabled", function()
            mason.is_enabled = false
            helpers.stub(vim.fn, "has", 1)

            plugin:health()

            assert.stub(vim.health.ok).was_called_with("Using `Neovim >= 0.11.0`")
            assert
                .stub(vim.health.error)
                .was_called_with("`ensure.plugin.mason` plugin is not enabled, LSPs won't be installed")
        end)
    end)

    describe("resolve_package", function()
        it("returns nil when mason is not enabled", function()
            mason.is_enabled = false

            local result = plugin:resolve_package("lua_ls")

            assert.is_nil(result)
        end)

        it("returns nil when executable is already available", function()
            mason.is_enabled = true
            helpers.stub(vim.fn, "executable", 1)

            ---@diagnostic disable-next-line: invisible
            vim.lsp.config._configs = {
                lua_ls = { cmd = { "lua-language-server" } },
            }

            local result = plugin:resolve_package("lua_ls")

            assert.is_nil(result)
        end)

        it("returns package name when executable is not available", function()
            mason.is_enabled = true
            helpers.stub(vim.fn, "executable", 0)
            helpers.stub(mason, "resolve_lsp", "lua-language-server")

            ---@diagnostic disable-next-line: invisible
            vim.lsp.config._configs = {
                lua_ls = { cmd = { "lua-language-server" } },
            }

            local result = plugin:resolve_package("lua_ls")

            assert.same("lua-language-server", result)
        end)

        it("handles function cmd that returns available executable", function()
            mason.is_enabled = true
            helpers.stub(vim.fn, "executable", 1)

            ---@diagnostic disable-next-line: invisible
            vim.lsp.config._configs = {
                lua_ls = {
                    cmd = function()
                        return { "lua-language-server" }
                    end,
                },
            }

            local result = plugin:resolve_package("lua_ls")

            assert.is_nil(result)
        end)

        it("handles function cmd that returns unavailable executable", function()
            mason.is_enabled = true
            helpers.stub(vim.fn, "executable", 0)
            helpers.stub(mason, "resolve_lsp", "lua-language-server")

            ---@diagnostic disable-next-line: invisible
            vim.lsp.config._configs = {
                lua_ls = {
                    cmd = function()
                        return { "lua-language-server" }
                    end,
                },
            }

            local result = plugin:resolve_package("lua_ls")

            assert.same("lua-language-server", result)
        end)

        it("uses resolve_tool as fallback when resolve_lsp returns nil", function()
            mason.is_enabled = true
            helpers.stub(vim.fn, "executable", 0)
            helpers.stub(mason, "resolve_lsp", nil)
            helpers.stub(mason, "resolve_tool", "some-tool")

            ---@diagnostic disable-next-line: invisible
            vim.lsp.config._configs = {
                some_lsp = { cmd = { "some-cmd" } },
            }

            local result = plugin:resolve_package("some_lsp")

            assert.same("some-tool", result)
        end)

        it("uses lsp_name as package when resolve returns true", function()
            mason.is_enabled = true
            helpers.stub(vim.fn, "executable", 0)
            helpers.stub(mason, "resolve_lsp", nil)
            helpers.stub(mason, "resolve_tool", nil)
            helpers.stub(mason, "resolve", { name = "custom_lsp" }) -- truthy value

            ---@diagnostic disable-next-line: invisible
            vim.lsp.config._configs = {
                custom_lsp = { cmd = { "custom-cmd" } },
            }

            local result = plugin:resolve_package("custom_lsp")

            assert.same("custom_lsp", result)
        end)

        it("returns nil when no config exists and no mapping found", function()
            mason.is_enabled = true
            helpers.stub(mason, "resolve_lsp", nil)
            helpers.stub(mason, "resolve_tool", nil)
            helpers.stub(mason, "resolve", nil)

            ---@diagnostic disable-next-line: invisible
            vim.lsp.config._configs = {}

            local result = plugin:resolve_package("unknown_lsp")

            assert.is_nil(result)
        end)
    end)

    describe("autoinstall", function()
        it("installs LSP packages via mason for matching filetype", function()
            mason.is_enabled = true
            plugin.auto = { enable = false, ignore = {}, multi = true }
            helpers.stub(mason, "install_packages")

            vim.lsp._enabled_configs = {
                lua_ls = {
                    resolved_config = { filetypes = { "lua", "vim" } },
                },
                ts_ls = {
                    resolved_config = { filetypes = { "typescript" } },
                },
            }

            helpers.stub(plugin, "resolve_package", function(_, lsp)
                if lsp == "lua_ls" then
                    return "lua-language-server"
                end
                return nil
            end)

            plugin:autoinstall("lua")

            assert
                .stub(mason.install_packages)
                .was_called_with(match.is_ref(mason), { "lua-language-server" }, match.is_function())
        end)

        it("does nothing when mason is not enabled", function()
            mason.is_enabled = false
            plugin.auto = { enable = false, ignore = {}, multi = true }
            helpers.stub(mason, "install_packages")

            vim.lsp._enabled_configs = {
                lua_ls = {
                    resolved_config = { filetypes = { "lua" } },
                },
            }

            plugin:autoinstall("lua")

            assert.stub(mason.install_packages).was_not_called()
        end)

        it("handles missing resolved_config gracefully", function()
            mason.is_enabled = true
            plugin.auto = { enable = false, ignore = {}, multi = true }
            helpers.stub(mason, "install_packages")

            vim.lsp._enabled_configs = {
                lua_ls = {}, -- No resolved_config
            }

            plugin:autoinstall("lua")

            assert.stub(mason.install_packages).was_called_with(match.is_ref(mason), {}, match.is_function())
        end)

        it("handles missing filetypes gracefully", function()
            mason.is_enabled = true
            plugin.auto = { enable = false, ignore = {}, multi = true }
            helpers.stub(mason, "install_packages")

            vim.lsp._enabled_configs = {
                lua_ls = {
                    resolved_config = {}, -- No filetypes
                },
            }

            plugin:autoinstall("lua")

            assert.stub(mason.install_packages).was_called_with(match.is_ref(mason), {}, match.is_function())
        end)
    end)

    describe("lsp.auto feature", function()
        it("does not run auto-detection when auto.enable is false", function()
            mason.is_enabled = true
            plugin.auto = { enable = false, ignore = {}, multi = true }
            helpers.stub(mason, "install_packages")
            helpers.stub(mason, "find_lsps_for_filetype")

            vim.lsp._enabled_configs = {}

            plugin:autoinstall("lua")

            assert.stub(mason.find_lsps_for_filetype).was_not_called()
        end)

        it("does not run auto-detection when an LSP is already enabled for the filetype", function()
            mason.is_enabled = true
            plugin.auto = { enable = true, ignore = {}, multi = true }
            helpers.stub(mason, "install_packages")
            helpers.stub(mason, "find_lsps_for_filetype")
            helpers.stub(plugin, "resolve_package", nil)

            vim.lsp._enabled_configs = {
                lua_ls = {
                    resolved_config = { filetypes = { "lua" } },
                },
            }

            plugin:autoinstall("lua")

            assert.stub(mason.find_lsps_for_filetype).was_not_called()
        end)

        it("runs auto-detection when auto.enable is true and no LSP is enabled", function()
            mason.is_enabled = true
            plugin.auto = { enable = true, ignore = {}, multi = true }
            helpers.stub(mason, "install_packages")
            helpers.stub(mason, "find_lsps_for_filetype", {})

            vim.lsp._enabled_configs = {}

            plugin:autoinstall("lua")

            assert.stub(mason.find_lsps_for_filetype).was_called_with(match.is_ref(mason), "lua")
        end)

        it("auto-enables single LSP when only one is available", function()
            mason.is_enabled = true
            plugin.auto = { enable = true, ignore = {}, multi = true }
            helpers.stub(mason, "install_packages")
            helpers.stub(mason, "find_lsps_for_filetype", {
                { lsp = "lua_ls", package = "lua-language-server" },
            })
            helpers.stub(plugin, "auto_enable_lsp")

            vim.lsp._enabled_configs = {}

            plugin:autoinstall("lua")

            assert
                .stub(plugin.auto_enable_lsp)
                .was_called_with(match.is_ref(plugin), { lsp = "lua_ls", package = "lua-language-server" }, "lua")
        end)

        it("prompts user selection when multiple LSPs are available and multi is true", function()
            mason.is_enabled = true
            plugin.auto = { enable = true, ignore = {}, multi = true }
            helpers.stub(mason, "install_packages")
            helpers.stub(mason, "find_lsps_for_filetype", {
                { lsp = "pyright", package = "pyright" },
                { lsp = "pylsp", package = "python-lsp-server" },
            })
            helpers.stub(plugin, "prompt_lsp_selection")

            vim.lsp._enabled_configs = {}

            plugin:autoinstall("python")

            assert.stub(plugin.prompt_lsp_selection).was_called_with(match.is_ref(plugin), {
                { lsp = "pyright", package = "pyright" },
                { lsp = "pylsp", package = "python-lsp-server" },
            }, "python")
        end)

        it("does nothing when multiple LSPs are available and multi is false", function()
            mason.is_enabled = true
            plugin.auto = { enable = true, ignore = {}, multi = false }
            helpers.stub(mason, "install_packages")
            helpers.stub(mason, "find_lsps_for_filetype", {
                { lsp = "pyright", package = "pyright" },
                { lsp = "pylsp", package = "python-lsp-server" },
            })
            helpers.stub(plugin, "auto_enable_lsp")
            helpers.stub(plugin, "prompt_lsp_selection")

            vim.lsp._enabled_configs = {}

            plugin:autoinstall("python")

            assert.stub(plugin.auto_enable_lsp).was_not_called()
            assert.stub(plugin.prompt_lsp_selection).was_not_called()
        end)

        it("still auto-enables single LSP when multi is false", function()
            mason.is_enabled = true
            plugin.auto = { enable = true, ignore = {}, multi = false }
            helpers.stub(mason, "install_packages")
            helpers.stub(mason, "find_lsps_for_filetype", {
                { lsp = "lua_ls", package = "lua-language-server" },
            })
            helpers.stub(plugin, "auto_enable_lsp")

            vim.lsp._enabled_configs = {}

            plugin:autoinstall("lua")

            assert
                .stub(plugin.auto_enable_lsp)
                .was_called_with(match.is_ref(plugin), { lsp = "lua_ls", package = "lua-language-server" }, "lua")
        end)

        it("does nothing when no LSPs are available from Mason", function()
            mason.is_enabled = true
            plugin.auto = { enable = true, ignore = {}, multi = true }
            helpers.stub(mason, "install_packages")
            helpers.stub(mason, "find_lsps_for_filetype", {})
            helpers.stub(plugin, "auto_enable_lsp")
            helpers.stub(plugin, "prompt_lsp_selection")

            vim.lsp._enabled_configs = {}

            plugin:autoinstall("unknown")

            assert.stub(plugin.auto_enable_lsp).was_not_called()
            assert.stub(plugin.prompt_lsp_selection).was_not_called()
        end)
    end)

    describe("lsp.auto.ignore feature", function()
        it("does not count ignored LSPs as enabled", function()
            mason.is_enabled = true
            plugin.auto = { enable = true, ignore = { "copilot" }, multi = true }
            helpers.stub(mason, "install_packages")
            helpers.stub(mason, "find_lsps_for_filetype", {
                { lsp = "lua_ls", package = "lua-language-server" },
            })
            helpers.stub(plugin, "resolve_package", nil)
            helpers.stub(plugin, "auto_enable_lsp")

            -- Only copilot is enabled for lua, but it's ignored
            vim.lsp._enabled_configs = {
                copilot = {
                    resolved_config = { filetypes = { "lua", "python", "javascript" } },
                },
            }

            plugin:autoinstall("lua")

            -- Should still run auto-detection since copilot is ignored
            assert.stub(mason.find_lsps_for_filetype).was_called_with(match.is_ref(mason), "lua")
            assert.stub(plugin.auto_enable_lsp).was_called()
        end)

        it("still installs packages for ignored LSPs", function()
            mason.is_enabled = true
            plugin.auto = { enable = true, ignore = { "copilot" }, multi = true }
            helpers.stub(mason, "install_packages")
            helpers.stub(mason, "find_lsps_for_filetype", {})
            helpers.stub(plugin, "resolve_package", function(_, lsp)
                if lsp == "copilot" then
                    return "copilot-language-server"
                end
                return nil
            end)

            vim.lsp._enabled_configs = {
                copilot = {
                    resolved_config = { filetypes = { "lua" } },
                },
            }

            plugin:autoinstall("lua")

            -- Copilot package should still be installed even though it's ignored
            assert
                .stub(mason.install_packages)
                .was_called_with(match.is_ref(mason), { "copilot-language-server" }, match.is_function())
        end)

        it("filters ignored LSPs from auto-detection results", function()
            mason.is_enabled = true
            plugin.auto = { enable = true, ignore = { "ltex", "ltex_plus" }, multi = true }
            helpers.stub(mason, "install_packages")
            helpers.stub(mason, "find_lsps_for_filetype", {
                { lsp = "lua_ls", package = "lua-language-server" },
                { lsp = "ltex", package = "ltex-ls" },
                { lsp = "ltex_plus", package = "ltex-ls-plus" },
            })
            helpers.stub(plugin, "auto_enable_lsp")

            vim.lsp._enabled_configs = {}

            plugin:autoinstall("lua")

            -- Should only auto-enable lua_ls, ignoring ltex and ltex_plus
            assert
                .stub(plugin.auto_enable_lsp)
                .was_called_with(match.is_ref(plugin), { lsp = "lua_ls", package = "lua-language-server" }, "lua")
        end)

        it("prompts selection only for non-ignored LSPs", function()
            mason.is_enabled = true
            plugin.auto = { enable = true, ignore = { "ltex" }, multi = true }
            helpers.stub(mason, "install_packages")
            helpers.stub(mason, "find_lsps_for_filetype", {
                { lsp = "pyright", package = "pyright" },
                { lsp = "pylsp", package = "python-lsp-server" },
                { lsp = "ltex", package = "ltex-ls" },
            })
            helpers.stub(plugin, "prompt_lsp_selection")

            vim.lsp._enabled_configs = {}

            plugin:autoinstall("python")

            -- ltex should be filtered out from the selection
            assert.stub(plugin.prompt_lsp_selection).was_called_with(match.is_ref(plugin), {
                { lsp = "pyright", package = "pyright" },
                { lsp = "pylsp", package = "python-lsp-server" },
            }, "python")
        end)

        it("does nothing when all available LSPs are ignored", function()
            mason.is_enabled = true
            plugin.auto = { enable = true, ignore = { "ltex", "ltex_plus" }, multi = true }
            helpers.stub(mason, "install_packages")
            helpers.stub(mason, "find_lsps_for_filetype", {
                { lsp = "ltex", package = "ltex-ls" },
                { lsp = "ltex_plus", package = "ltex-ls-plus" },
            })
            helpers.stub(plugin, "auto_enable_lsp")
            helpers.stub(plugin, "prompt_lsp_selection")

            vim.lsp._enabled_configs = {}

            plugin:autoinstall("markdown")

            -- All available LSPs are ignored, so nothing should happen
            assert.stub(plugin.auto_enable_lsp).was_not_called()
            assert.stub(plugin.prompt_lsp_selection).was_not_called()
        end)

        it("counts non-ignored LSPs as enabled to prevent auto-detection", function()
            mason.is_enabled = true
            plugin.auto = { enable = true, ignore = { "copilot" }, multi = true }
            helpers.stub(mason, "install_packages")
            helpers.stub(mason, "find_lsps_for_filetype")
            helpers.stub(plugin, "resolve_package", nil)

            -- Both copilot (ignored) and lua_ls (not ignored) are enabled
            vim.lsp._enabled_configs = {
                copilot = {
                    resolved_config = { filetypes = { "lua" } },
                },
                lua_ls = {
                    resolved_config = { filetypes = { "lua" } },
                },
            }

            plugin:autoinstall("lua")

            -- lua_ls is enabled and not ignored, so auto-detection should not run
            assert.stub(mason.find_lsps_for_filetype).was_not_called()
        end)
    end)

    describe("auto_enable_lsp", function()
        it("installs package and enables LSP on success", function()
            helpers.stub(mason, "try_install", function(_, _, callback)
                callback()
            end)
            helpers.stub(vim.lsp, "enable")

            plugin:auto_enable_lsp({ lsp = "lua_ls", package = "lua-language-server" }, "lua")

            assert
                .stub(mason.try_install)
                .was_called_with(match.is_ref(mason), "lua-language-server", match.is_function())
            assert.stub(vim.lsp.enable).was_called_with("lua_ls")
        end)
    end)

    describe("prompt_lsp_selection", function()
        -- Helper to call prompt_lsp_selection inside a coroutine (as the function requires)
        local function call_in_coroutine(fn)
            local coro = coroutine.create(fn)
            coroutine.resume(coro)
            return coro
        end

        it("calls vim.ui.select with LSP options and format_item", function()
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
                { lsp = "pyright", package = "pyright" },
                { lsp = "pylsp", package = "python-lsp-server" },
            }

            call_in_coroutine(function()
                plugin:prompt_lsp_selection(available, "python")
            end)

            assert.stub(vim.ui.select).was_called()
            assert.equals(2, #captured_items)
            assert.equals("pyright", captured_items[1].lsp)
            assert.equals("pylsp", captured_items[2].lsp)
            assert.matches("python", captured_opts.prompt)
            -- Test format_item returns LSP name
            assert.equals("pyright", captured_opts.format_item(captured_items[1]))
        end)

        it("auto-enables selected LSP when user makes a choice", function()
            -- Stub vim.schedule to execute immediately
            helpers.stub(vim, "schedule", function(fn)
                fn()
            end)

            local select_callback
            helpers.stub(vim.ui, "select", function(_, _, callback)
                select_callback = callback
            end)
            helpers.stub(plugin, "auto_enable_lsp")

            local available = {
                { lsp = "pyright", package = "pyright" },
                { lsp = "pylsp", package = "python-lsp-server" },
            }
            local pylsp_entry = available[2]

            local coro = call_in_coroutine(function()
                plugin:prompt_lsp_selection(available, "python")
            end)

            -- Simulate user selecting pylsp entry
            select_callback(pylsp_entry)

            -- Wait for coroutine to complete
            assert.equals("dead", coroutine.status(coro))

            assert.stub(plugin.auto_enable_lsp).was_called_with(match.is_ref(plugin), pylsp_entry, "python")
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
            helpers.stub(plugin, "auto_enable_lsp")

            local available = {
                { lsp = "pyright", package = "pyright" },
            }

            local coro = call_in_coroutine(function()
                plugin:prompt_lsp_selection(available, "python")
            end)

            -- Simulate user canceling (nil choice)
            select_callback(nil)

            -- Wait for coroutine to complete
            assert.equals("dead", coroutine.status(coro))

            assert.stub(plugin.auto_enable_lsp).was_not_called()
        end)
    end)

    describe("install", function()
        it("installs packages for enabled LSPs", function()
            mason.is_enabled = true
            helpers.stub(mason, "install_packages")
            helpers.stub(plugin, "resolve_package", function(_, lsp)
                if lsp == "lua_ls" then
                    return "lua-language-server"
                end
                return nil
            end)

            vim.lsp._enabled_configs = {
                lua_ls = {},
            }

            plugin:install()

            assert
                .stub(mason.install_packages)
                .was_called_with(match.is_ref(mason), { "lua-language-server" }, match.is_function())
        end)

        it("does nothing when mason is not enabled", function()
            mason.is_enabled = false
            helpers.stub(mason, "install_packages")

            vim.lsp._enabled_configs = {
                lua_ls = {},
            }

            plugin:install()

            assert.stub(mason.install_packages).was_not_called()
        end)

        it("installs all configured LSPs when opts.all is true", function()
            mason.is_enabled = true
            helpers.stub(mason, "install_packages")
            helpers.stub(plugin, "resolve_package", function(_, lsp)
                if lsp == "lua_ls" then
                    return "lua-language-server"
                elseif lsp == "pyright" then
                    return "pyright"
                end
                return nil
            end)

            vim.lsp._enabled_configs = {}
            ---@diagnostic disable-next-line: invisible
            vim.lsp.config._configs = {
                lua_ls = {},
                pyright = {},
            }

            plugin:install({ all = true })

            assert.stub(mason.install_packages).was_called()
        end)
    end)
end)

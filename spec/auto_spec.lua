local helpers = require("spec.helpers")
local match = require("luassert.match")

describe("ensure.auto", function()
    local auto = require("ensure.auto")

    before_each(function()
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

    describe("DEFAULT_CONFIG", function()
        it("has expected default values", function()
            assert.is_false(auto.DEFAULT_CONFIG.enable)
            assert.same({}, auto.DEFAULT_CONFIG.ignore)
            assert.is_true(auto.DEFAULT_CONFIG.multi)
        end)
    end)

    describe("normalize", function()
        it("returns defaults when auto is nil", function()
            local result = auto.normalize(nil)

            assert.is_table(result)
            assert.is_false(result.enable)
            assert.same({}, result.ignore)
            assert.is_true(result.multi)
        end)

        it("normalizes boolean true to table with enable=true", function()
            local result = auto.normalize(true)

            assert.is_table(result)
            assert.is_true(result.enable)
            assert.same({}, result.ignore)
            assert.is_true(result.multi)
        end)

        it("normalizes boolean false to table with enable=false", function()
            local result = auto.normalize(false)

            assert.is_table(result)
            assert.is_false(result.enable)
            assert.same({}, result.ignore)
            assert.is_true(result.multi)
        end)

        it("merges table config with defaults", function()
            local result = auto.normalize({
                enable = true,
                ignore = { "prettier" },
            })

            assert.is_table(result)
            assert.is_true(result.enable)
            assert.same({ "prettier" }, result.ignore)
            assert.is_true(result.multi) -- default
        end)

        it("allows overriding multi to false", function()
            local result = auto.normalize({
                enable = true,
                multi = false,
            })

            assert.is_table(result)
            assert.is_true(result.enable)
            assert.is_false(result.multi)
        end)

        it("merges plugin-specific defaults", function()
            local result = auto.normalize(true, { ignore = { "copilot", "ltex" } })

            assert.is_table(result)
            assert.is_true(result.enable)
            assert.same({ "copilot", "ltex" }, result.ignore)
            assert.is_true(result.multi)
        end)

        it("user config is merged with plugin-specific defaults", function()
            local result = auto.normalize({ ignore = { "custom" } }, { ignore = { "copilot", "ltex" } })

            assert.is_table(result)
            -- User ignore list is merged with defaults
            assert.same({ "copilot", "ltex", "custom" }, result.ignore)
        end)

        it("returns deep copy to avoid mutation", function()
            local result1 = auto.normalize(nil)
            local result2 = auto.normalize(nil)

            result1.enable = true
            assert.is_false(result2.enable)
        end)
    end)

    describe("should_ignore", function()
        it("returns true for tool in global list", function()
            local ignore = { "prettier", "biome" }
            assert.is_true(auto.should_ignore(ignore, "prettier", "javascript"))
        end)

        it("returns false for tool not in global list", function()
            local ignore = { "prettier" }
            assert.is_false(auto.should_ignore(ignore, "biome", "javascript"))
        end)

        it("returns true for tool in filetype-specific list", function()
            local ignore = { javascript = { "prettier" } }
            assert.is_true(auto.should_ignore(ignore, "prettier", "javascript"))
        end)

        it("returns false for tool not in filetype-specific list", function()
            local ignore = { javascript = { "prettier" } }
            assert.is_false(auto.should_ignore(ignore, "biome", "javascript"))
        end)

        it("returns false when filetype has no ignore list", function()
            local ignore = { javascript = { "prettier" } }
            assert.is_false(auto.should_ignore(ignore, "prettier", "python"))
        end)

        it("returns true for any tool when filetype is disabled with '*'", function()
            local ignore = { markdown = "*" }
            assert.is_true(auto.should_ignore(ignore, "prettier", "markdown"))
            assert.is_true(auto.should_ignore(ignore, "any_tool", "markdown"))
        end)

        it("returns false for other filetypes when one is disabled", function()
            local ignore = { markdown = "*" }
            assert.is_false(auto.should_ignore(ignore, "prettier", "javascript"))
        end)

        it("returns true for tool in global list items", function()
            local ignore = { "codespell", "typos" }
            assert.is_true(auto.should_ignore(ignore, "codespell", "python"))
            assert.is_true(auto.should_ignore(ignore, "typos", "javascript"))
        end)

        it("checks both filetype-specific and global list items", function()
            local ignore = {
                "codespell",
                python = { "pylint" },
            }
            assert.is_true(auto.should_ignore(ignore, "codespell", "python"))
            assert.is_true(auto.should_ignore(ignore, "pylint", "python"))
            assert.is_false(auto.should_ignore(ignore, "ruff", "python"))
        end)
    end)

    describe("is_disabled_for_ft", function()
        it("returns false for list format", function()
            local ignore = { "prettier" }
            assert.is_false(auto.is_disabled_for_ft(ignore, "javascript"))
        end)

        it("returns true when filetype is disabled with '*'", function()
            local ignore = { markdown = "*" }
            assert.is_true(auto.is_disabled_for_ft(ignore, "markdown"))
        end)

        it("returns false for other filetypes", function()
            local ignore = { markdown = "*" }
            assert.is_false(auto.is_disabled_for_ft(ignore, "javascript"))
        end)

        it("returns false when filetype has tool list", function()
            local ignore = { javascript = { "prettier" } }
            assert.is_false(auto.is_disabled_for_ft(ignore, "javascript"))
        end)
    end)

    describe("merge_ignore", function()
        it("returns base when override is empty", function()
            local base = { "prettier" }
            local override = {}
            assert.same({ "prettier" }, auto.merge_ignore(base, override))
        end)

        it("returns override when base is empty", function()
            local base = {}
            local override = { "biome" }
            assert.same({ "biome" }, auto.merge_ignore(base, override))
        end)

        it("concatenates two lists with unique values", function()
            local base = { "prettier", "biome" }
            local override = { "biome", "eslint" }
            assert.same({ "prettier", "biome", "eslint" }, auto.merge_ignore(base, override))
        end)

        it("merges two filetype tables", function()
            local base = { python = { "pylint" } }
            local override = { javascript = { "prettier" } }
            local result = auto.merge_ignore(base, override)
            assert.same({ "pylint" }, result.python)
            assert.same({ "prettier" }, result.javascript)
        end)

        it("merges tool lists for same filetype", function()
            local base = { python = { "pylint" } }
            local override = { python = { "mypy" } }
            local result = auto.merge_ignore(base, override)
            assert.same({ "pylint", "mypy" }, result.python)
        end)

        it("override '*' takes precedence", function()
            local base = { markdown = { "prettier" } }
            local override = { markdown = "*" }
            local result = auto.merge_ignore(base, override)
            assert.equals("*", result.markdown)
        end)

        it("merges global list with filetype-specific ignores", function()
            local base = { "prettier" }
            local override = { python = { "pylint" } }
            local result = auto.merge_ignore(base, override)
            assert.equals("prettier", result[1])
            assert.same({ "pylint" }, result.python)
        end)

        it("merges mixed tables with both global and filetype-specific", function()
            local base = { "codespell", python = { "pylint" } }
            local override = { "typos", javascript = { "prettier" } }
            local result = auto.merge_ignore(base, override)
            assert.equals("codespell", result[1])
            assert.equals("typos", result[2])
            assert.same({ "pylint" }, result.python)
            assert.same({ "prettier" }, result.javascript)
        end)
    end)

    describe("AutoManager", function()
        local manager
        local find_available_stub
        local is_configured_stub
        local configure_stub
        local mason_mock

        before_each(function()
            find_available_stub = function()
                return {}
            end
            is_configured_stub = function()
                return false
            end
            configure_stub = function() end
            mason_mock = {
                try_install = function(_, _, callback)
                    callback()
                end,
            }

            manager = auto.AutoManager:new({
                mason = mason_mock,
                kind = "tool",
                find_available = function(ft)
                    return find_available_stub(ft)
                end,
                is_configured = function(ft)
                    return is_configured_stub(ft)
                end,
                configure = function(entry, ft)
                    configure_stub(entry, ft)
                end,
            })
        end)

        describe("new", function()
            it("creates manager with default config", function()
                assert.is_table(manager.config)
                assert.is_false(manager.config.enable)
            end)

            it("initializes empty prompt queue", function()
                assert.is_true(manager.prompts:is_empty())
            end)

            it("normalizes and stores config from opts.config", function()
                local custom_manager = auto.AutoManager:new({
                    config = true,
                    mason = mason_mock,
                    kind = "tool",
                    find_available = function()
                        return {}
                    end,
                    is_configured = function()
                        return false
                    end,
                    configure = function() end,
                })

                assert.is_true(custom_manager.config.enable)
            end)

            it("uses plugin-specific defaults", function()
                local custom_manager = auto.AutoManager:new({
                    config = true,
                    defaults = { ignore = { "copilot" } },
                    mason = mason_mock,
                    kind = "LSP",
                    find_available = function()
                        return {}
                    end,
                    is_configured = function()
                        return false
                    end,
                    configure = function() end,
                })

                assert.same({ "copilot" }, custom_manager.config.ignore)
            end)
        end)

        describe("trigger", function()
            it("does nothing when auto.enable is false", function()
                manager.config = auto.normalize(false)
                local was_called = false
                find_available_stub = function()
                    was_called = true
                    return {}
                end

                manager:trigger("lua")

                assert.is_false(was_called)
            end)

            it("enqueues filetype when auto.enable is true", function()
                manager.config = auto.normalize(true)

                manager:trigger("lua")

                assert.is_true(manager.prompts:seen("lua"))
            end)

            it("does not enqueue same filetype twice", function()
                manager.config = auto.normalize(true)

                manager:trigger("lua")
                manager:trigger("lua")

                -- Queue should still have only one entry
                assert.equals(0, manager.prompts:size()) -- Already processed
            end)
        end)

        describe("process_queue / guess_for_filetype", function()
            it("does nothing when tool is already configured", function()
                manager.config = auto.normalize(true)
                is_configured_stub = function()
                    return true
                end
                local was_called = false
                find_available_stub = function()
                    was_called = true
                    return {}
                end

                manager:trigger("lua")

                assert.is_false(was_called)
            end)

            it("does nothing when no tools are available", function()
                manager.config = auto.normalize(true)
                find_available_stub = function()
                    return {}
                end
                local was_called = false
                configure_stub = function()
                    was_called = true
                end

                manager:trigger("lua")

                assert.is_false(was_called)
            end)

            it("auto-enables single available tool", function()
                manager.config = auto.normalize(true)
                find_available_stub = function()
                    return { { tool = "stylua", package = "stylua" } }
                end
                local configured_entry, configured_ft
                configure_stub = function(entry, ft)
                    configured_entry = entry
                    configured_ft = ft
                end

                manager:trigger("lua")

                assert.same({ tool = "stylua", package = "stylua" }, configured_entry)
                assert.equals("lua", configured_ft)
            end)

            it("filters out ignored tools", function()
                manager.config = auto.normalize({ enable = true, ignore = { "prettier" } })
                find_available_stub = function()
                    return {
                        { tool = "biome", package = "biome" },
                        { tool = "prettier", package = "prettier" },
                    }
                end
                local configured_entry
                configure_stub = function(entry)
                    configured_entry = entry
                end

                manager:trigger("javascript")

                -- Should only enable biome, ignoring prettier
                assert.same({ tool = "biome", package = "biome" }, configured_entry)
            end)

            it("does nothing when all available tools are ignored", function()
                manager.config = auto.normalize({ enable = true, ignore = { "prettier", "biome" } })
                find_available_stub = function()
                    return {
                        { tool = "prettier", package = "prettier" },
                        { tool = "biome", package = "biome" },
                    }
                end
                local was_called = false
                configure_stub = function()
                    was_called = true
                end

                manager:trigger("javascript")

                assert.is_false(was_called)
            end)

            it("does nothing when multiple tools available and multi is false", function()
                manager.config = auto.normalize({ enable = true, multi = false })
                find_available_stub = function()
                    return {
                        { tool = "black", package = "black" },
                        { tool = "ruff", package = "ruff" },
                    }
                end
                local was_called = false
                configure_stub = function()
                    was_called = true
                end

                manager:trigger("python")

                assert.is_false(was_called)
            end)

            it("filters out filetype-specific ignored tools", function()
                manager.config = auto.normalize({
                    enable = true,
                    ignore = { javascript = { "prettier" } },
                })
                find_available_stub = function()
                    return {
                        { tool = "biome", package = "biome" },
                        { tool = "prettier", package = "prettier" },
                    }
                end
                local configured_entry
                configure_stub = function(entry)
                    configured_entry = entry
                end

                manager:trigger("javascript")

                -- Should only enable biome, ignoring prettier for javascript
                assert.same({ tool = "biome", package = "biome" }, configured_entry)
            end)

            it("does not filter tool for other filetypes", function()
                manager.config = auto.normalize({
                    enable = true,
                    ignore = { javascript = { "prettier" } },
                })
                find_available_stub = function()
                    return {
                        { tool = "prettier", package = "prettier" },
                    }
                end
                local configured_entry
                configure_stub = function(entry)
                    configured_entry = entry
                end

                manager:trigger("css")

                -- prettier is not ignored for css, only for javascript
                assert.same({ tool = "prettier", package = "prettier" }, configured_entry)
            end)

            it("does nothing when filetype is disabled with '*'", function()
                manager.config = auto.normalize({
                    enable = true,
                    ignore = { markdown = "*" },
                })
                find_available_stub = function()
                    return {
                        { tool = "prettier", package = "prettier" },
                    }
                end
                local was_called = false
                configure_stub = function()
                    was_called = true
                end

                manager:trigger("markdown")

                assert.is_false(was_called)
            end)

            it("filters global list items for all filetypes", function()
                manager.config = auto.normalize({
                    enable = true,
                    ignore = { "codespell" },
                })
                find_available_stub = function()
                    return {
                        { tool = "ruff", package = "ruff" },
                        { tool = "codespell", package = "codespell" },
                    }
                end
                local configured_entry
                configure_stub = function(entry)
                    configured_entry = entry
                end

                manager:trigger("python")

                -- codespell should be filtered out globally
                assert.same({ tool = "ruff", package = "ruff" }, configured_entry)
            end)
        end)

        describe("enable", function()
            it("notifies user and calls mason try_install then configure", function()
                local installed_pkg
                helpers.stub(mason_mock, "try_install", function(_, pkg, callback)
                    installed_pkg = pkg
                    callback()
                end)

                local configured_entry, configured_ft
                configure_stub = function(entry, ft)
                    configured_entry = entry
                    configured_ft = ft
                end

                manager:enable({ tool = "stylua", package = "stylua" }, "lua")

                assert.stub(vim.notify).was_called()
                assert.equals("stylua", installed_pkg)
                assert.same({ tool = "stylua", package = "stylua" }, configured_entry)
                assert.equals("lua", configured_ft)
            end)
        end)

        describe("prompt_selection", function()
            -- Helper to call prompt selection inside a coroutine
            local function call_in_coroutine(fn)
                local coro = coroutine.create(fn)
                coroutine.resume(coro)
                return coro
            end

            it("calls vim.ui.select with correct options", function()
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
                    manager:prompt_selection(available, "python")
                end)

                assert.stub(vim.ui.select).was_called()
                assert.equals(2, #captured_items)
                assert.matches("Select a tool for python:", captured_opts.prompt)
                assert.equals("black", captured_opts.format_item(captured_items[1]))
            end)

            it("calls enable for selected tool", function()
                helpers.stub(vim, "schedule", function(fn)
                    fn()
                end)

                local select_callback
                helpers.stub(vim.ui, "select", function(_, _, callback)
                    select_callback = callback
                end)

                local configured_entry
                configure_stub = function(entry)
                    configured_entry = entry
                end

                local available = {
                    { tool = "black", package = "black" },
                    { tool = "ruff", package = "ruff" },
                }

                local coro = call_in_coroutine(function()
                    manager:prompt_selection(available, "python")
                end)

                -- Simulate user selecting ruff
                select_callback(available[2])

                assert.equals("dead", coroutine.status(coro))
                assert.same({ tool = "ruff", package = "ruff" }, configured_entry)
            end)

            it("does nothing when user cancels", function()
                helpers.stub(vim, "schedule", function(fn)
                    fn()
                end)

                local select_callback
                helpers.stub(vim.ui, "select", function(_, _, callback)
                    select_callback = callback
                end)

                local was_called = false
                configure_stub = function()
                    was_called = true
                end

                local available = {
                    { tool = "black", package = "black" },
                }

                local coro = call_in_coroutine(function()
                    manager:prompt_selection(available, "python")
                end)

                -- Simulate user canceling
                select_callback(nil)

                assert.equals("dead", coroutine.status(coro))
                assert.is_false(was_called)
            end)
        end)

        describe("clear_prompt_queue", function()
            it("clears queue", function()
                manager.config = auto.normalize(true)
                manager.prompts:enqueue("lua")

                manager:clear_prompt_queue()

                assert.is_true(manager.prompts:is_empty())
            end)
        end)
    end)

    describe("reset", function()
        it("clears all managers' queues", function()
            local mason_mock = { try_install = function() end }
            local manager1 = auto.AutoManager:new({
                config = true,
                find_available = function()
                    return {}
                end,
                is_configured = function()
                    return false
                end,
                configure = function() end,
                mason = mason_mock,
                kind = "Formatter",
            })
            local manager2 = auto.AutoManager:new({
                config = true,
                find_available = function()
                    return {}
                end,
                is_configured = function()
                    return false
                end,
                configure = function() end,
                mason = mason_mock,
                kind = "Linter",
            })

            manager1.prompts:enqueue("lua")
            manager2.prompts:enqueue("python")

            auto.reset()

            assert.is_true(manager1.prompts:is_empty())
            assert.is_true(manager2.prompts:is_empty())
        end)

        it("clears session choices", function()
            -- Simulate a stored session choice (JSON encoded for session persistence)
            vim.g.EnsureAutoChoices = vim.json.encode({
                Formatter = { lua = { tool = "stylua", package = "stylua" } },
            })

            auto.reset()

            assert.same({}, auto.get_session_choices())
        end)
    end)

    describe("session persistence", function()
        local manager
        local configure_stub
        local mason_mock

        before_each(function()
            configure_stub = function() end
            mason_mock = {
                try_install = function(_, _, callback)
                    callback()
                end,
            }

            manager = auto.AutoManager:new({
                config = true,
                mason = mason_mock,
                kind = "Formatter",
                find_available = function()
                    return {
                        { tool = "stylua", package = "stylua" },
                        { tool = "luaformatter", package = "luaformatter" },
                    }
                end,
                is_configured = function()
                    return false
                end,
                configure = function(entry, ft)
                    configure_stub(entry, ft)
                end,
            })
        end)

        describe("get_session_choices", function()
            it("returns empty table when no choices stored", function()
                vim.g.EnsureAutoChoices = nil
                assert.same({}, auto.get_session_choices())
            end)

            it("returns stored choices", function()
                local choices = {
                    Formatter = { lua = { tool = "stylua", package = "stylua" } },
                }
                vim.g.EnsureAutoChoices = vim.json.encode(choices)
                assert.same(choices, auto.get_session_choices())
            end)
        end)

        describe("clear_session_choices", function()
            it("clears all stored choices", function()
                vim.g.EnsureAutoChoices = vim.json.encode({
                    Formatter = { lua = { tool = "stylua", package = "stylua" } },
                })

                auto.clear_session_choices()

                assert.is_nil(vim.g.EnsureAutoChoices)
            end)
        end)

        describe("storing choices", function()
            it("stores choice when auto-enabling single tool", function()
                manager = auto.AutoManager:new({
                    config = true,
                    mason = mason_mock,
                    kind = "Formatter",
                    find_available = function()
                        return { { tool = "stylua", package = "stylua" } }
                    end,
                    is_configured = function()
                        return false
                    end,
                    configure = function() end,
                })

                manager:trigger("lua")

                local choices = auto.get_session_choices()
                assert.is_not_nil(choices.Formatter)
                assert.same({ tool = "stylua", package = "stylua" }, choices.Formatter.lua)
            end)

            it("stores choice when user selects from multiple options", function()
                helpers.stub(vim, "schedule", function(fn)
                    fn()
                end)

                local select_callback
                helpers.stub(vim.ui, "select", function(_, _, callback)
                    select_callback = callback
                end)

                local available = {
                    { tool = "black", package = "black" },
                    { tool = "ruff", package = "ruff" },
                }

                local coro = coroutine.create(function()
                    manager:prompt_selection(available, "python")
                end)
                coroutine.resume(coro)

                -- Simulate user selecting ruff
                select_callback(available[2])

                local choices = auto.get_session_choices()
                assert.is_not_nil(choices.Formatter)
                assert.same({ tool = "ruff", package = "ruff" }, choices.Formatter.python)
            end)

            it("stores choices per kind (Formatter, Linter, LSP)", function()
                local lsp_manager = auto.AutoManager:new({
                    config = true,
                    mason = mason_mock,
                    kind = "LSP server",
                    find_available = function()
                        return { { tool = "lua_ls", package = "lua-language-server" } }
                    end,
                    is_configured = function()
                        return false
                    end,
                    configure = function() end,
                })

                manager = auto.AutoManager:new({
                    config = true,
                    mason = mason_mock,
                    kind = "Formatter",
                    find_available = function()
                        return { { tool = "stylua", package = "stylua" } }
                    end,
                    is_configured = function()
                        return false
                    end,
                    configure = function() end,
                })

                lsp_manager:trigger("lua")
                manager:trigger("lua")

                local choices = auto.get_session_choices()
                assert.same({ tool = "lua_ls", package = "lua-language-server" }, choices["LSP server"].lua)
                assert.same({ tool = "stylua", package = "stylua" }, choices.Formatter.lua)
            end)
        end)

        describe("restoring choices", function()
            it("uses stored choice instead of prompting", function()
                vim.g.EnsureAutoChoices = vim.json.encode({
                    Formatter = { lua = { tool = "stylua", package = "stylua" } },
                })

                local configured_entry
                configure_stub = function(entry)
                    configured_entry = entry
                end

                -- This manager has multiple tools, but stored choice should be used
                manager = auto.AutoManager:new({
                    config = true,
                    mason = mason_mock,
                    kind = "Formatter",
                    find_available = function()
                        return {
                            { tool = "stylua", package = "stylua" },
                            { tool = "luaformatter", package = "luaformatter" },
                        }
                    end,
                    is_configured = function()
                        return false
                    end,
                    configure = function(entry, ft)
                        configure_stub(entry, ft)
                    end,
                })

                local ui_select_called = false
                helpers.stub(vim.ui, "select", function()
                    ui_select_called = true
                end)

                manager:trigger("lua")

                -- Should use stored choice, not prompt
                assert.is_false(ui_select_called)
                assert.same({ tool = "stylua", package = "stylua" }, configured_entry)
            end)

            it("does not overwrite stored choice when restoring", function()
                vim.g.EnsureAutoChoices = vim.json.encode({
                    Formatter = { lua = { tool = "stylua", package = "stylua" } },
                })

                manager = auto.AutoManager:new({
                    config = true,
                    mason = mason_mock,
                    kind = "Formatter",
                    find_available = function()
                        return { { tool = "stylua", package = "stylua" } }
                    end,
                    is_configured = function()
                        return false
                    end,
                    configure = function() end,
                })

                -- Trigger restore
                manager:trigger("lua")

                -- Choice should still be stored (not duplicated or modified)
                local choices = auto.get_session_choices()
                assert.same({ tool = "stylua", package = "stylua" }, choices.Formatter.lua)
            end)

            it("prompts for filetypes not in stored choices", function()
                vim.g.EnsureAutoChoices = vim.json.encode({
                    Formatter = { lua = { tool = "stylua", package = "stylua" } },
                })

                helpers.stub(vim, "schedule", function(fn)
                    fn()
                end)

                local select_called = false
                helpers.stub(vim.ui, "select", function()
                    select_called = true
                end)

                -- This manager has multiple tools for python (not stored)
                manager = auto.AutoManager:new({
                    config = true,
                    mason = mason_mock,
                    kind = "Formatter",
                    find_available = function()
                        return {
                            { tool = "black", package = "black" },
                            { tool = "ruff", package = "ruff" },
                        }
                    end,
                    is_configured = function()
                        return false
                    end,
                    configure = function() end,
                })

                local coro = coroutine.create(function()
                    manager:guess_for_filetype("python")
                end)
                coroutine.resume(coro)

                -- Should prompt for python since it's not in stored choices
                assert.is_true(select_called)
            end)
        end)
    end)
end)

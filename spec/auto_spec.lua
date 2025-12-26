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

        it("user config overrides plugin-specific defaults", function()
            local result = auto.normalize({ ignore = { "custom" } }, { ignore = { "copilot", "ltex" } })

            assert.is_table(result)
            assert.same({ "custom" }, result.ignore)
        end)

        it("returns deep copy to avoid mutation", function()
            local result1 = auto.normalize(nil)
            local result2 = auto.normalize(nil)

            result1.enable = true
            assert.is_false(result2.enable)
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
    end)
end)

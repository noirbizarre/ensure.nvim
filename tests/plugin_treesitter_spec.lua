local helpers = require("tests.helpers")
local match = require("luassert.match")

describe("ensure.plugin.treesitter", function()
    before_each(function()
        helpers.mock(vim.health, true)
    end)

    after_each(function()
        helpers.teardown()
    end)

    local ts_plugin = require("ensure.plugin.treesitter")

    local function stub_ts()
        local ts = {
            get_available = function(mode)
                if mode == 1 then
                    return { "lua" }
                elseif mode == 2 then
                    return { "python" }
                else
                    return { "lua", "python", "rust" }
                end
            end,
            get_installed = function()
                return { "lua" }
            end,
            install = function() end,
        }
        package.loaded["nvim-treesitter"] = ts
        return ts
    end

    it("setup stores parsers/ignore and triggers install when nvim-treesitter is available", function()
        local ts = stub_ts()
        helpers.stub(ts, "install")

        ts_plugin:setup({
            parsers = { "lua", "rust" },
            ignore = { parsers = { "rust" } },
        })

        assert.is_true(ts_plugin.is_installed)
        assert.same({ "lua", "rust" }, ts_plugin.parsers)
        assert.same({ "rust" }, ts_plugin.ignore)

        assert.stub(ts.install).was_called()
    end)

    it("health reports missing nvim-treesitter", function()
        ts_plugin.is_installed = false

        ts_plugin:health()

        assert.stub(vim.health.error).was_called_with("`nvim-treesitter` is not installed")
    end)

    it("autoinstall installs parser for current filetype when available and not ignored", function()
        local ts = stub_ts()
        helpers.stub(ts, "install")

        ts_plugin.is_installed = true
        ts_plugin.ignore = { "rust" }

        ts_plugin:autoinstall("python")
        assert.stub(ts.install).was_called_with({ "python" })

        ts.install:revert()
        helpers.stub(ts, "install")
        ts_plugin:autoinstall("rust")
        assert.stub(ts.install).was_not_called()
    end)

    it("install installs missing, non-ignored parsers; all=true uses available list", function()
        local ts = stub_ts()
        helpers.stub(ts, "install")

        ts_plugin.is_installed = true
        ts_plugin.parsers = { "lua", "python", "rust" }
        ts_plugin.ignore = { "rust" }

        ts_plugin:install()

        assert.stub(ts.install).was_called_with({ "python" })

        ts.install:revert()
        helpers.stub(ts, "install")

        ts_plugin.parsers = nil
        ts_plugin.ignore = {}
        ts_plugin:install({ all = true })

        assert.stub(ts.install).was_called_with({ "python" })
    end)
end)

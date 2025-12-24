local helpers = require("tests.helpers")

describe("ensure.notify", function()
    after_each(function()
        helpers.teardown()
    end)

    local notify = require("ensure.notify")

    it("uses INFO as default log level", function()
        helpers.stub(vim, "notify")

        notify("Hello")

        assert.stub(vim.notify).was_called_with("Hello", vim.log.levels.INFO, match.is_table())
    end)

    it("forwards provided log level to vim.notify", function()
        helpers.stub(vim, "notify")

        notify("Warn", vim.log.levels.WARN)

        assert.stub(vim.notify).was_called_with("Warn", vim.log.levels.WARN, match.is_table())
    end)
end)

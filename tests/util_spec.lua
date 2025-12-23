local util = require("ensure.util")

describe("ensure.util", function()
    describe("string_list", function()
        it("wraps string into list", function()
            local result = util.string_list("foo")
            assert.same({ "foo" }, result)
        end)

        it("returns table as is", function()
            local value = { "foo", "bar" }
            local result = util.string_list(value)
            assert.same(value, result)
        end)

        it("handles empty table", function()
            local result = util.string_list({})
            assert.same({}, result)
        end)
    end)
end)

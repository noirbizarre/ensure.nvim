local assert = require("luassert.assert")

---  Matcher that checks if a table contains specified key-value pairs
local function table_with(state, arguments)
    return function(tbl)
        if type(tbl) ~= "table" then
            return false
        end
        for key, value in pairs(arguments[1]) do
            if type(key) == "string" then
                if tbl[key] ~= value then
                    return false
                end
            else
                if not vim.tbl_contains(tbl, value) then
                    return false
                end
            end
        end
        return true
    end
end

assert:register("matcher", "table_with", table_with)

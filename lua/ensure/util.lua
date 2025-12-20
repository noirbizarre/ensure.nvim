local M = {}

---@param value string|string[]
---@return string[]
function M.string_list(value)
    if type(value) == "string" then
        return { value }
    else
        return value
    end
end

return M

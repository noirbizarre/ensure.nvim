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

---A basic queue implementation.
---@class ensure.Queue
---@field first number
---@field last number
---@field items table<number, any>
local Queue = {}

function Queue:new()
    local obj = { position = 0, items = {} }
    setmetatable(obj, self)
    self.__index = self
    return obj
end

function Queue:enqueue(item)
    table.insert(self.items, item)
end

function Queue:dequeue()
    if self.position >= #self.items then
        return nil
    end
    self.position = self.position + 1
    return self.items[self.position]
end

function Queue:size()
    return #self.items - self.position
end

function Queue:is_empty()
    return self.position >= #self.items
end

function Queue:seen(item)
    for _, value in ipairs(self.items) do
        if value == item then
            return true
        end
    end
    return false
end

function Queue:clear()
    self.position = 0
    self.items = {}
end

M.Queue = Queue

return M

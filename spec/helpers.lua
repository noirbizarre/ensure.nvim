require("spec.matchers")

local M = {}

local clean_functions = {}
local revertables = {}

---Mock `require()` to simulate missing modules
---@@param ... module names to mock as missing
function M.modules_not_found(...)
    local original_require = require
    local missing = {}
    for i = 1, select("#", ...) do
        local mod = select(i, ...)
        missing[mod] = true
    end

    _G.require = function(name)
        if missing[name] then
            error("module not found")
        end
        return original_require(name)
    end

    table.insert(clean_functions, function()
        _G.require = original_require
    end)
end

---Create a stub that will be reverted on teardown
---@param object table The object to stub
---@param key string The key to stub
---@param ... any Additional arguments to pass to stub
---@return luassert.spy The created stub
function M.stub(object, key, ...)
    local stub = require("luassert.stub")
    stub(object, key, ...)
    table.insert(revertables, object[key])
    return object[key]
end

---Create a mock that will be reverted on teardown
---@param object table The object to mock
---@param doStub boolean Whether to stub methods
function M.mock(object, doStub)
    local mock = require("luassert.mock")
    mock(object, doStub)
    table.insert(clean_functions, function()
        mock.revert(object)
    end)
    return object
end

---@class StubbedPlugin : ensure.Plugin
---@field methods table<string, luassert.spy> The mocked methods of the plugin

---Create a stubbed plugin module that will be cleaned up on teardown
---@param import string The module path to stub
---@param attrs? table<string, any> Attributes to set on the stubbed plugin
---@return StubbedPlugin The stubbed plugin
function M.plugin(import, attrs)
    local Plugin = require("ensure.plugin")
    local plugin = Plugin:new()

    local metatable = vim.deepcopy(getmetatable(plugin))
    M.mock(metatable.__index, true)
    plugin = setmetatable(plugin, metatable)
    plugin.methods = metatable.__index

    for k, v in pairs(attrs or {}) do
        plugin[k] = v
    end

    package.loaded[import] = plugin
    table.insert(clean_functions, function()
        package.loaded[import] = nil
    end)

    ---@diagnostic disable-next-line: return-type-mismatch
    return plugin
end

---Flush pending vim.schedule callbacks by running the event loop briefly
---@param timeout? number Timeout in ms (default 10)
function M.flush_schedule(timeout)
    -- vim.wait with a short timeout allows scheduled callbacks to execute
    vim.wait(timeout or 10, function()
        return false
    end, 1)
end

---Cleanup all stubs and mocks
function M.teardown()
    for _, fn in ipairs(clean_functions) do
        fn()
    end
    for _, r in ipairs(revertables) do
        r:revert()
    end
    clean_functions = {}
    revertables = {}
end

return M

---@class ensure.Plugin
local Plugin = {}

---Initialize the plugin
---@param opts ensure.Config
---@diagnostic disable-next-line: unused-local
function Plugin:setup(opts) end

---Check plugin health
function Plugin:health() end

---Auto-install requirements for open buffer (if applicable)
---@param ft string filetype of the current buffer
---@diagnostic disable-next-line: unused-local
function Plugin:autoinstall(ft) end

---A subcommand to use for this plugin (if applicable)
---@type string?
Plugin.command = nil


---Install declared packages/dependencies
---@param opts? ensure.CommandOpts
---@diagnostic disable-next-line: unused-local
function Plugin:install(opts) end

---Instantiate a new Plugin
function Plugin:new()
    local obj = setmetatable({}, { __index = self })
    return obj
end

return Plugin

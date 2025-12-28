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

---Dump session choices as configuration lines
---Override in plugins that support auto-detection to add their specific configuration
---@param choices ensure.AutoChoices The stored session choices
---@param lines string[] The lines array to append configuration to
---@diagnostic disable-next-line: unused-local
function Plugin:dump_session(choices, lines) end

---Instantiate a new Plugin
function Plugin:new()
    local obj = setmetatable({}, { __index = self })
    return obj
end

return Plugin

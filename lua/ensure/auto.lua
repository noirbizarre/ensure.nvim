local notify = require("ensure.notify")
local util = require("ensure.util")

local M = {}

---@class ensure.AutoConfig
---@field enable boolean Enable auto-detection for filetypes with no configured tool
---@field ignore string[] Tools to ignore in auto-detection mode
---@field multi boolean If true, prompt user to select when multiple tools match

---@alias ensure.Auto boolean|ensure.AutoConfig

---Default values for auto-detection config
---@type ensure.AutoConfig
M.DEFAULT_CONFIG = {
    enable = false,
    ignore = {},
    multi = true,
}

---Normalize auto config to a full table
---Accepts boolean (shorthand), table (partial config), or nil
---@param auto boolean|ensure.AutoConfig|nil User-provided auto config
---@param defaults? ensure.AutoConfig Plugin-specific defaults to merge with
---@return ensure.AutoConfig Normalized configuration table
function M.normalize(auto, defaults)
    local base = vim.tbl_extend("force", M.DEFAULT_CONFIG, defaults or {})
    if type(auto) == "boolean" then
        return vim.tbl_extend("force", base, { enable = auto })
    elseif type(auto) == "table" then
        return vim.tbl_extend("force", base, auto)
    else
        return vim.deepcopy(base)
    end
end

---@class ensure.AutoEntry
---@field tool string The tool or LSP name
---@field package string The Mason package name

---@class ensure.AutoManagerOpts
---@field config boolean|ensure.AutoConfig|nil User-provided auto config
---@field defaults? ensure.AutoConfig Plugin-specific default config values
---@field find_available fun(ft: string): ensure.AutoEntry[] Find available tools for a filetype
---@field is_configured fun(ft: string): boolean Check if a tool is already configured for a filetype
---@field configure fun(entry: ensure.AutoEntry, ft: string) Configure a tool for a filetype (called after install)
---@field mason ensure.MasonPlugin Mason plugin instance for installing packages
---@field kind string Singular form of the tool kind (e.g., "formatter", "linter", "LSP")

-- Global prompt state shared across all AutoManager instances
-- User can only have one prompt displayed at a time
local prompt_active = false

-- Global registry of all AutoManager instances
-- Used to process all pending prompts across all managers
---@type ensure.AutoManager[]
local managers = {}

---@class ensure.AutoManager
---@field config ensure.AutoConfig Normalized auto-detection configuration
---@field opts ensure.AutoManagerOpts Callbacks and options
---@field prompts ensure.Queue Prompt queue for filetypes
local AutoManager = {}
AutoManager.__index = AutoManager

---Create a new AutoManager instance
---@param opts ensure.AutoManagerOpts
---@return ensure.AutoManager
function AutoManager:new(opts)
    local obj = {
        config = M.normalize(opts.config, opts.defaults),
        opts = opts,
        prompts = util.Queue:new(),
    }
    setmetatable(obj, self)
    table.insert(managers, obj)
    return obj
end

---Trigger auto-detection for a filetype if conditions are met
---Should be called from the plugin's autoinstall method when no tool is configured
---@param ft string The filetype to check
function AutoManager:trigger(ft)
    if not self.config.enable then
        return
    end

    if self.prompts:seen(ft) then
        return
    end

    self.prompts:enqueue(ft)
    vim.defer_fn(function()
        self:process_queue()
    end, 500)
end

---Process the prompt queue
---Uses a coroutine to handle async user prompts sequentially
---Processes all managers' queues to ensure no prompts are lost
function AutoManager:process_queue()
    if prompt_active then
        return
    end

    prompt_active = true

    coroutine.resume(coroutine.create(function()
        -- Process all managers' queues, not just this one
        local has_pending = true
        while has_pending do
            has_pending = false
            for _, manager in ipairs(managers) do
                while not manager.prompts:is_empty() do
                    has_pending = true
                    local ft = manager.prompts:dequeue()
                    manager:guess_for_filetype(ft)
                end
            end
        end

        prompt_active = false
    end))
end

---Guess and potentially auto-enable a tool for a filetype
---@param ft string The filetype
function AutoManager:guess_for_filetype(ft)
    -- Re-check if a tool is now configured (may have changed during defer)
    if self.opts.is_configured(ft) then
        return
    end

    -- Find available tools for this filetype
    local available = self.opts.find_available(ft)

    -- Filter out ignored tools
    available = vim.tbl_filter(function(entry)
        return not vim.list_contains(self.config.ignore, entry.tool)
    end, available)

    if #available == 0 then
        return
    end

    if #available == 1 then
        -- Single match: auto-enable immediately
        self:enable(available[1], ft)
    elseif self.config.multi then
        -- Multiple matches and multi is enabled: prompt user to select
        self:prompt_selection(available, ft)
    end
end

---Enable a tool for a filetype
---Notifies the user, installs via mason, then calls the configure callback
---@param entry ensure.AutoEntry The tool entry to enable
---@param ft string The filetype
function AutoManager:enable(entry, ft)
    notify(("Auto-enabling `%s` for filetype `%s`"):format(entry.tool, ft))
    self.opts.mason:try_install(entry.package, function()
        self.opts.configure(entry, ft)
        notify(("%s `%s` enabled. Add it to your config for persistence."):format(self.opts.kind, entry.tool))
    end)
end

---@async
---Prompt user to select a tool from multiple options
---@param available ensure.AutoEntry[]
---@param ft string
function AutoManager:prompt_selection(available, ft)
    local coro = assert(coroutine.running())

    vim.schedule(function()
        vim.ui.select(available, {
            prompt = ("Select a %s for %s:"):format(self.opts.kind, ft),
            format_item = function(item)
                return item.tool
            end,
        }, function(choice)
            coroutine.resume(coro, choice)
        end)
    end)

    local choice = coroutine.yield()
    if choice then
        self:enable(choice, ft)
    end
end

---Clear prompt queue (for testing)
function AutoManager:clear_prompt_queue()
    self.prompts:clear()
end

M.AutoManager = AutoManager

---Reset all global state (for testing)
---Clears all managers' queues and resets the prompt_active flag
function M.reset()
    for _, manager in ipairs(managers) do
        manager.prompts:clear()
    end
    prompt_active = false
end

return M

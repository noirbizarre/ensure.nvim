local notify = require("ensure.notify")
local util = require("ensure.util")

local M = {}

-- Session persistence storage key
-- Must start with uppercase and contain lowercase for Neovim session persistence
-- Value is stored as JSON string since only String/Number types are persisted
-- Note: Requires "globals" in vim.opt.sessionoptions for session managers to persist this
local SESSION_KEY = "EnsureAutoChoices"

---@class ensure.AutoChoices
---@field [string] table<string, ensure.AutoEntry> Map of kind -> filetype -> chosen entry

---Get stored choices from session storage
---Decodes from JSON string for session persistence compatibility
---@return ensure.AutoChoices
local function get_session_choices()
    local stored = vim.g[SESSION_KEY]
    if not stored or stored == "" then
        return {}
    end
    local ok, choices = pcall(vim.json.decode, stored)
    if ok and type(choices) == "table" then
        return choices
    end
    return {}
end

---Save choices to session storage
---Encodes as JSON string for session persistence compatibility
---@param choices ensure.AutoChoices
local function set_session_choices(choices)
    if vim.tbl_isempty(choices) then
        vim.g[SESSION_KEY] = nil
    else
        vim.g[SESSION_KEY] = vim.json.encode(choices)
    end
end

---Store a user's choice for a filetype and kind
---@param kind string The tool kind (e.g., "Formatter", "Linter", "LSP server")
---@param ft string The filetype
---@param entry ensure.AutoEntry The chosen entry
local function store_choice(kind, ft, entry)
    local choices = get_session_choices()
    if not choices[kind] then
        choices[kind] = {}
    end
    choices[kind][ft] = entry
    set_session_choices(choices)
end

---Get a stored choice for a filetype and kind
---@param kind string The tool kind
---@param ft string The filetype
---@return ensure.AutoEntry|nil The stored entry, or nil if none
local function get_stored_choice(kind, ft)
    local choices = get_session_choices()
    if choices[kind] then
        return choices[kind][ft]
    end
    return nil
end

---@alias ensure.AutoIgnore string[]|table<string, string[]|"*">

---@class ensure.AutoConfig
---@field enable boolean Enable auto-detection for filetypes with no configured tool
---@field ignore ensure.AutoIgnore Tools to ignore in auto-detection mode (global list or per-filetype)
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
        -- Deep merge ignore tables if both are tables with filetype keys
        local result = vim.tbl_extend("force", base, auto)
        -- If user provided ignore, merge with base ignore
        if auto.ignore and base.ignore then
            result.ignore = M.merge_ignore(base.ignore, auto.ignore)
        end
        return result
    else
        return vim.deepcopy(base)
    end
end

---Merge two ignore configs
---Handles mixed table format: { "global1", "global2", javascript = { "prettier" }, markdown = "*" }
---@param base ensure.AutoIgnore Base ignore config (from defaults)
---@param override ensure.AutoIgnore Override ignore config (from user)
---@return ensure.AutoIgnore Merged ignore config
function M.merge_ignore(base, override)
    -- If override is empty, return base
    if vim.tbl_isempty(override) then
        return vim.deepcopy(base)
    end

    -- If base is empty, return override
    if vim.tbl_isempty(base) then
        return vim.deepcopy(override)
    end

    local result = vim.deepcopy(base)

    -- Merge global ignores (list items / numeric keys)
    for _, v in ipairs(override) do
        if not vim.list_contains(result, v) then
            table.insert(result, v)
        end
    end

    -- Merge filetype-specific ignores (string keys)
    for ft, tools in pairs(override) do
        if type(ft) == "string" then
            if tools == "*" then
                result[ft] = "*"
            elseif result[ft] == "*" then
                -- Keep the disable
                result[ft] = "*"
            elseif type(result[ft]) == "table" then
                -- Merge tool lists
                for _, tool in ipairs(tools) do
                    if not vim.list_contains(result[ft], tool) then
                        table.insert(result[ft], tool)
                    end
                end
            else
                result[ft] = vim.deepcopy(tools)
            end
        end
    end

    return result
end

---Check if a tool should be ignored for a filetype
---Supports mixed table format: { "global1", "global2", javascript = { "prettier" }, markdown = "*" }
---@param ignore ensure.AutoIgnore The ignore config
---@param tool string The tool name
---@param ft string The filetype
---@return boolean True if the tool should be ignored
function M.should_ignore(ignore, tool, ft)
    -- Check filetype-specific ignore (string keys)
    local ft_ignore = ignore[ft]
    if ft_ignore == "*" then
        return true -- Disable auto for this filetype entirely
    elseif type(ft_ignore) == "table" and vim.list_contains(ft_ignore, tool) then
        return true
    end

    -- Check global ignore (list items / numeric keys)
    for _, v in ipairs(ignore) do
        if v == tool then
            return true
        end
    end

    return false
end

---Check if auto-detection is disabled for a filetype
---@param ignore ensure.AutoIgnore The ignore config
---@param ft string The filetype
---@return boolean True if auto-detection is disabled for this filetype
function M.is_disabled_for_ft(ignore, ft)
    return ignore[ft] == "*"
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
    -- Check if auto-detection is disabled for this filetype
    if M.is_disabled_for_ft(self.config.ignore, ft) then
        return
    end

    -- Re-check if a tool is now configured (may have changed during defer)
    if self.opts.is_configured(ft) then
        return
    end

    -- Check for a stored session choice first
    local stored = get_stored_choice(self.opts.kind, ft)
    if stored then
        -- Restore the previous session choice without prompting
        self:enable(stored, ft, true)
        return
    end

    -- Find available tools for this filetype
    local available = self.opts.find_available(ft)

    -- Filter out ignored tools
    available = vim.tbl_filter(function(entry)
        return not M.should_ignore(self.config.ignore, entry.tool, ft)
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
---@param from_session? boolean Whether this is a restore from session (skip storage)
function AutoManager:enable(entry, ft, from_session)
    notify(("Auto-enabling `%s` for filetype `%s`"):format(entry.tool, ft))
    -- Store the choice for session persistence (unless restoring from session)
    if not from_session then
        store_choice(self.opts.kind, ft, entry)
    end
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

---Clear all stored session choices
---@return nil
function M.clear_session_choices()
    vim.g[SESSION_KEY] = nil
end

---Get all stored session choices (for debugging/testing)
---@return ensure.AutoChoices
function M.get_session_choices()
    return get_session_choices()
end

---Reset all global state (for testing)
---Clears all managers' queues, resets the prompt_active flag, and clears session choices
function M.reset()
    for _, manager in ipairs(managers) do
        manager.prompts:clear()
    end
    prompt_active = false
    M.clear_session_choices()
end

return M

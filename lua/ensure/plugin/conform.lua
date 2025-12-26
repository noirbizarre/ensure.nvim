local Plugin = require("ensure.plugin")
local mason = require("ensure.plugin.mason")
local notify = require("ensure.notify")
local util = require("ensure.util")

---@class ensure.ConformPlugin : ensure.Plugin
---@field auto ToolAutoConfig Normalized auto-detection configuration
local M = Plugin:new()

---Default values for auto-detection config
---@type ToolAutoConfig
local AUTO_DEFAULTS = {
    enable = false,
    ignore = {},
    multi = true,
}

local CONFIG_KEYS = { "auto" }

-- Prompt queue state (module-level)
local prompts = util.Queue:new()
local prompt_active = false

---Resolve a formatter name to a Mason package name
---Uses the formatter's command to find the corresponding Mason package
---Returns nil if the formatter is already available or not found in Mason
---@param formatter_name string The conform formatter name
---@param bufnr? integer Buffer number for context (default: current buffer)
---@return string|nil The Mason package name, or nil if not needed/found
function M:resolve_package(formatter_name, bufnr)
    if not mason.is_enabled then
        return nil
    end

    local conform = require("conform")
    local info = conform.get_formatter_info(formatter_name, bufnr)

    if not info or not info.command then
        return nil
    end

    -- Skip if the formatter is already available
    if info.available then
        return nil
    end

    -- Extract executable name from command (handles full paths)
    local exe_name = vim.fn.fnamemodify(info.command, ":t")

    return mason:resolve_tool(exe_name)
end

---Normalize formatters.auto config to a table
---@param auto boolean|ToolAutoConfig|nil
---@return ToolAutoConfig
local function normalize_auto(auto)
    if type(auto) == "boolean" then
        return vim.tbl_extend("force", AUTO_DEFAULTS, { enable = auto })
    elseif type(auto) == "table" then
        return vim.tbl_extend("force", AUTO_DEFAULTS, auto)
    else
        return vim.deepcopy(AUTO_DEFAULTS)
    end
end

function M:setup(opts)
    self.is_installed, _ = pcall(require, "conform")
    if not self.is_installed then
        return
    end

    self.auto = normalize_auto(opts.formatters.auto)

    local conform = require("conform")
    for ft, formatters in pairs(opts.formatters) do
        if not vim.list_contains(CONFIG_KEYS, ft) then
            conform.formatters_by_ft[ft] = util.string_list(formatters)
        end
    end
end

function M:health()
    if self.is_installed then
        vim.health.ok("`conform.nvim` is installed")
    else
        vim.health.error("`conform.nvim` is not installed")
    end
    if mason.is_enabled then
        vim.health.ok("`ensure.plugin.mason` plugin is enabled")
    else
        vim.health.warn("`ensure.plugin.mason` plugin is not enabled, formatters won't be installed")
    end
end

function M:autoinstall(ft)
    if not self.is_installed or not mason.is_enabled then
        return
    end

    local conform = require("conform")
    local bufnr = vim.api.nvim_get_current_buf()
    local formatters = conform.list_formatters_for_buffer(bufnr)
    local has_configured_formatter = formatters and #formatters > 0

    if formatters then
        local packages = {}
        for _, formatter in ipairs(formatters) do
            local pkg = self:resolve_package(formatter, bufnr)
            if pkg then
                table.insert(packages, pkg)
            end
        end
        mason:install_packages(packages)
    end

    -- Auto-detection: defer to allow formatters to resolve
    if not has_configured_formatter and self.auto.enable and not prompts:seen(ft) then
        prompts:enqueue(ft)
        vim.defer_fn(function()
            self:guess_autoinstalls()
        end, 500)
    end
end

function M:guess_autoinstalls()
    if prompt_active then
        return
    end

    prompt_active = true

    coroutine.resume(coroutine.create(function()
        while not prompts:is_empty() do
            local ft = prompts:dequeue()
            self:guess_autoinstall_for_filetype(ft)
        end

        prompt_active = false
    end))
end

function M:guess_autoinstall_for_filetype(ft)
    local conform = require("conform")

    -- Re-check if any formatter is now configured for this filetype
    local configured = conform.formatters_by_ft[ft]
    if configured and #configured > 0 then
        return -- Formatter is configured, don't auto-detect
    end

    -- Find available formatters for this filetype from Mason
    local available = mason:find_formatters_for_filetype(ft)

    -- Filter out ignored formatters from available options
    available = vim.tbl_filter(function(entry)
        return not vim.list_contains(self.auto.ignore, entry.tool)
    end, available)

    if #available == 0 then
        return
    end

    if #available == 1 then
        -- Single match: auto-install and enable
        self:auto_enable_formatter(available[1], ft)
    elseif self.auto.multi then
        -- Multiple matches and multi is enabled: prompt user to select
        self:prompt_formatter_selection(available, ft)
    end
end

---Auto-enable a single formatter for a filetype
---@param entry {tool: string, package: string}
---@param ft string
function M:auto_enable_formatter(entry, ft)
    notify(("Auto-enabling `%s` for filetype `%s`"):format(entry.tool, ft))
    mason:try_install(entry.package, function()
        local conform = require("conform")
        conform.formatters_by_ft[ft] = { entry.tool }
        notify(("Formatter `%s` enabled. Add it to your config for persistence."):format(entry.tool))
    end)
end

---@async
---Prompt user to select a formatter from multiple options (queued)
---@param available {tool: string, package: string}[]
---@param ft string
function M:prompt_formatter_selection(available, ft)
    local coro = assert(coroutine.running())

    vim.schedule(function()
        vim.ui.select(available, {
            prompt = ("Select formatter for %s:"):format(ft),
            format_item = function(item)
                return item.tool
            end,
        }, function(choice)
            coroutine.resume(coro, choice)
        end)
    end)
    local choice = coroutine.yield()
    if choice then
        self:auto_enable_formatter(choice, ft)
    end
end

---Only for testing: clear prompt queue and reset active state
function M:clear_prompt_queue()
    prompts:clear()
    prompt_active = false
end

M.command = "formatters"

function M:install()
    if not self.is_installed or not mason.is_enabled then
        return
    end

    local conform = require("conform")
    local packages = {}
    local known_formatters = vim.tbl_keys(require("conform.formatters").list_all_formatters())

    for _, info in pairs(conform.list_all_formatters()) do
        -- Only install known formatters
        if vim.tbl_contains(known_formatters, info.name) then
            local pkg = self:resolve_package(info.name)
            if pkg then
                table.insert(packages, pkg)
            end
        end
    end

    if #packages > 0 then
        mason:install_packages(packages)
    end
end

return M

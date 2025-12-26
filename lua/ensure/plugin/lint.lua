local Plugin = require("ensure.plugin")
local mason = require("ensure.plugin.mason")
local notify = require("ensure.notify")
local util = require("ensure.util")

---@class ensure.LintPlugin : ensure.Plugin
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

---Resolve a linter name to a Mason package name
---Uses the linter's command to find the corresponding Mason package
---Returns nil if the linter is already available or not found in Mason
---@param linter_name string The nvim-lint linter name
---@return string|nil The Mason package name, or nil if not needed/found
function M:resolve_package(linter_name)
    if not mason.is_enabled then
        return nil
    end

    local lint = require("lint")
    local linter = lint.linters[linter_name]

    if not linter then
        return nil
    end

    -- Handle linter as factory function
    if type(linter) == "function" then
        local ok, result = pcall(linter)
        if not ok then
            return nil
        end
        linter = result
    end

    local cmd = linter.cmd
    if not cmd then
        return nil
    end

    -- Handle cmd as function (dynamic resolution)
    if type(cmd) == "function" then
        local ok, result = pcall(cmd)
        if not ok or not result then
            return nil
        end
        cmd = result
    end

    -- Skip if the linter command is already executable
    if vim.fn.executable(cmd) == 1 then
        return nil
    end

    -- Extract executable name from command (handles full paths)
    local exe_name = vim.fn.fnamemodify(cmd, ":t")

    return mason:resolve_tool(exe_name)
end

---Normalize linters.auto config to a table
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
    self.is_installed, _ = pcall(require, "lint")
    if not self.is_installed then
        return
    end

    self.auto = normalize_auto(opts.linters.auto)

    local lint = require("lint")
    for ft, linters in pairs(opts.linters) do
        if not vim.list_contains(CONFIG_KEYS, ft) then
            lint.linters_by_ft[ft] = util.string_list(linters)
        end
    end
end

function M:health()
    if self.is_installed then
        vim.health.ok("`nvim-lint` is installed")
    else
        vim.health.error("`nvim-lint` is not installed")
    end
    if require("ensure.plugin.mason").is_enabled then
        vim.health.ok("`ensure.plugin.mason` plugin is enabled")
    else
        vim.health.warn("`ensure.plugin.mason` plugin is not enabled, linters won't be installed")
    end
end

function M:autoinstall(ft)
    if not self.is_installed or not mason.is_enabled then
        return
    end

    local lint = require("lint")
    local linters = lint._resolve_linter_by_ft(ft)
    local has_configured_linter = linters and #linters > 0
    local packages = {}

    for _, linter in ipairs(linters) do
        local pkg = self:resolve_package(linter)
        if pkg then
            table.insert(packages, pkg)
        end
    end
    if #packages > 0 then
        mason:install_packages(packages)
    end

    -- Auto-detection: defer to allow linters to resolve
    if not has_configured_linter and self.auto.enable and not prompts:seen(ft) then
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
    local lint = require("lint")

    -- Re-check if any linter is now configured for this filetype
    local configured = lint.linters_by_ft[ft]
    if configured and #configured > 0 then
        return -- Linter is configured, don't auto-detect
    end

    -- Find available linters for this filetype from Mason
    local available = mason:find_linters_for_filetype(ft)

    -- Filter out ignored linters from available options
    available = vim.tbl_filter(function(entry)
        return not vim.list_contains(self.auto.ignore, entry.tool)
    end, available)

    if #available == 0 then
        return
    end

    if #available == 1 then
        -- Single match: auto-install and enable
        self:auto_enable_linter(available[1], ft)
    elseif self.auto.multi then
        -- Multiple matches and multi is enabled: prompt user to select
        self:prompt_linter_selection(available, ft)
    end
end

---Auto-enable a single linter for a filetype
---@param entry {tool: string, package: string}
---@param ft string
function M:auto_enable_linter(entry, ft)
    notify(("Auto-enabling `%s` for filetype `%s`"):format(entry.tool, ft))
    mason:try_install(entry.package, function()
        local lint = require("lint")
        lint.linters_by_ft[ft] = { entry.tool }
        notify(("Linter `%s` enabled. Add it to your config for persistence."):format(entry.tool))
    end)
end

---@async
---Prompt user to select a linter from multiple options (queued)
---@param available {tool: string, package: string}[]
---@param ft string
function M:prompt_linter_selection(available, ft)
    local coro = assert(coroutine.running())

    vim.schedule(function()
        vim.ui.select(available, {
            prompt = ("Select linter for %s:"):format(ft),
            format_item = function(item)
                return item.tool
            end,
        }, function(choice)
            coroutine.resume(coro, choice)
        end)
    end)
    local choice = coroutine.yield()
    if choice then
        self:auto_enable_linter(choice, ft)
    end
end

---Only for testing: clear prompt queue and reset active state
function M:clear_prompt_queue()
    prompts:clear()
    prompt_active = false
end

M.command = "linters"

function M:install()
    if not self.is_installed or not mason.is_enabled then
        return
    end

    local lint = require("lint")
    local packages = {}

    for _, linters in pairs(lint.linters_by_ft) do
        for _, linter in ipairs(linters) do
            local pkg = self:resolve_package(linter)
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

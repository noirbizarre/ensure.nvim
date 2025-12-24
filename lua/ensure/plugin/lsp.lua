local Plugin = require("ensure.plugin")
local mason = require("ensure.plugin.mason")
local notify = require("ensure.notify")
local util = require("ensure.util")

---@class ensure.LspPlugin : ensure.Plugin
---@field auto LspAutoConfig Normalized auto-detection configuration
local M = Plugin:new()

---Default values for auto-detection config
---@type LspAutoConfig
local AUTO_DEFAULTS = {
    enable = false,
    ignore = { "copilot", "ltex", "ltex_plus" },
    multi = true,
}

local CONFIG_KEYS = { "enable", "disable", "auto" }

-- Prompt queue state (module-level)
local prompts = util.Queue:new()
local prompt_active = false

---Reset prompt queue state (for testing)
-- function M:reset_prompt_queue()
--     prompt_queue = {}
--     prompt_active = false
-- end

---Resolve an LSP server name to a Mason package name
---Returns nil if the LSP server is already available or not found in Mason
---@param lsp_name string The LSP server name
---@return string|nil The Mason package name, or nil if not needed/found
function M:resolve_package(lsp_name)
    if not mason.is_enabled then
        return nil
    end

    -- Get the LSP config to check if it's available
    ---@diagnostic disable-next-line: invisible
    local config = vim.lsp.config._configs[lsp_name]
    if config and config.cmd then
        local cmd = config.cmd
        -- cmd can be a table (command + args) or a function
        if type(cmd) == "table" and #cmd > 0 then
            local executable = cmd[1]
            if vim.fn.executable(executable) == 1 then
                return nil -- Already available
            end
        elseif type(cmd) == "function" then
            -- For dynamic commands, we can't easily check availability
            -- Try to call it and check the result
            local ok, result = pcall(cmd)
            if ok and type(result) == "table" and #result > 0 then
                local executable = result[1]
                if vim.fn.executable(executable) == 1 then
                    return nil -- Already available
                end
            end
        end
    end

    -- Use the mapping to get the Mason package name
    local package = mason:resolve_lsp(lsp_name)
    if package then
        return package
    end

    -- Fallback: check if the lsp_name itself is a valid Mason package
    return mason:resolve_tool(lsp_name) or mason:resolve(lsp_name) and lsp_name or nil
end

---Normalize lsp.auto config to a table
---@param auto boolean|LspAutoConfig|nil
---@return LspAutoConfig
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
    self.auto = normalize_auto(opts.lsp.auto)

    local to_enable = {}
    for _, lsp in pairs(opts.lsp.enable) do
        if not vim.list_contains(opts.lsp.disable, lsp) then
            table.insert(to_enable, lsp)
        end
    end
    if #to_enable > 0 then
        vim.lsp.enable(to_enable)
    end

    for name, config in pairs(opts.lsp) do
        if not vim.list_contains(CONFIG_KEYS, name) then
            if type(config) == "function" then
                config = config()
            end
            vim.lsp.config(name, config)
        end
    end
end

function M:health()
    if vim.fn.has("nvim-0.11.0") == 1 then
        vim.health.ok("Using `Neovim >= 0.11.0`")
    else
        vim.health.error("`Neovim >= 0.11.0` is required")
        return
    end

    if require("ensure.plugin.mason").is_enabled then
        vim.health.ok("`ensure.plugin.mason` plugin is enabled")
    else
        vim.health.error("`ensure.plugin.mason` plugin is not enabled, LSPs won't be installed")
    end
end

function M:autoinstall(ft)
    if not mason.is_enabled then
        return
    end

    local packages = {}
    local has_enabled_lsp = false

    --- List required LSP packages for this filetype
    for lsp, config in pairs(vim.lsp._enabled_configs) do
        if
            config.resolved_config
            and config.resolved_config.filetypes
            and vim.list_contains(config.resolved_config.filetypes, ft)
        then
            -- Only count as "enabled" if not in auto.ignore list
            if not vim.list_contains(self.auto.ignore, lsp) then
                has_enabled_lsp = true
            end
            -- Install packages for all enabled LSPs
            local pkg = self:resolve_package(lsp)
            if pkg then
                table.insert(packages, pkg)
            end
        end
    end

    mason:install_packages(packages, function(package)
        -- Restart the LSP for the current buffer if it was just installed
        local lsp = mason:lsp_from_package(package) or package
        vim.lsp.enable(lsp, false)
        vim.lsp.enable(lsp, true)
    end)

    -- Auto-detection: defer to allow LSP configs to resolve
    if not has_enabled_lsp and self.auto.enable and not prompts:seen(ft) then
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
    -- Re-check if any non-ignored LSP is now enabled for this filetype
    for lsp, config in pairs(vim.lsp._enabled_configs) do
        if
            config.resolved_config
            and config.resolved_config.filetypes
            and vim.list_contains(config.resolved_config.filetypes, ft)
            and not vim.list_contains(self.auto.ignore, lsp)
        then
            return -- LSP is enabled, don't auto-detect
        end
    end
    -- Find available LSPs for this filetype from Mason
    local available = mason:find_lsps_for_filetype(ft)

    -- Filter out ignored LSPs from available options
    available = vim.tbl_filter(function(entry)
        return not vim.list_contains(self.auto.ignore, entry.lsp)
    end, available)

    if #available == 0 then
        return
    end

    if #available == 1 then
        -- Single match: auto-install and enable
        self:auto_enable_lsp(available[1], ft)
    elseif self.auto.multi then
        -- Multiple matches and multi is enabled: prompt user to select
        self:prompt_lsp_selection(available, ft)
    end
end

---Auto-enable a single LSP for a filetype
---@param entry {lsp: string, package: string}
---@param ft string
function M:auto_enable_lsp(entry, ft)
    notify(("Auto-enabling `%s` for filetype `%s`"):format(entry.lsp, ft))
    mason:try_install(entry.package, function()
        vim.lsp.enable(entry.lsp)
        notify(("LSP `%s` enabled. Add it to your config for persistence."):format(entry.lsp))
    end)
end

---@async
---Prompt user to select an LSP from multiple options (queued)
---@param available {lsp: string, package: string}[]
---@param ft string
function M:prompt_lsp_selection(available, ft)
    local coro = assert(coroutine.running())

    vim.schedule(function()
        vim.ui.select(available, {
            prompt = ("Select LSP for %s:"):format(ft),
            format_item = function(item)
                return item.lsp
            end,
        }, function(choice)
            coroutine.resume(coro, choice)
        end)
    end)
    local choice = coroutine.yield()
    if choice then
        self:auto_enable_lsp(choice, ft)
    end
end

---Only for testing: clear prompt queue and reset active state
function M:clear_prompt_queue()
    prompts:clear()
    prompt_active = false
end

M.command = "lsps"

function M:install(opts)
    if not mason.is_enabled then
        return
    end

    local packages = {}
    local candidates = opts and opts.all and vim.lsp.config._configs or vim.lsp._enabled_configs
    --- Install all configured LSP servers
    ---@diagnostic disable-next-line: invisible
    for lsp, _ in pairs(candidates) do
        local pkg = self:resolve_package(lsp)
        if pkg then
            table.insert(packages, pkg)
        end
    end

    if #packages > 0 then
        mason:install_packages(packages, function(package)
            -- Restart the LSP for the current buffer if it was just installed
            local lsp = mason:lsp_from_package(package) or package
            vim.lsp.enable(lsp, false)
            vim.lsp.enable(lsp, true)
        end)
    end
end

return M

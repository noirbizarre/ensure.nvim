local Plugin = require("ensure.plugin")
local auto = require("ensure.auto")
local mason = require("ensure.plugin.mason")
local util = require("ensure.util")

---@class ensure.LintPlugin : ensure.Plugin
---@field auto ensure.AutoManager Auto-manager instance
local M = Plugin:new()

---Default ignore list for linter auto-detection
---These are typo/spelling/grammar checkers that shouldn't trigger auto-detection
local LINTER_DEFAULT_IGNORE = {
    "alex",
    "codespell",
    "cspell",
    "misspell",
    "proselint",
    "textlint",
    "typos",
    "vale",
    "woke",
    "write_good",
}

local CONFIG_KEYS = { "auto" }

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

function M:setup(opts)
    self.is_installed, _ = pcall(require, "lint")
    if not self.is_installed then
        return
    end

    -- Create auto-manager with plugin-specific callbacks
    self.auto = auto.AutoManager:new({
        config = opts.linters.auto,
        defaults = { ignore = LINTER_DEFAULT_IGNORE },
        mason = mason,
        kind = "Linter",
        find_available = function(ft)
            return mason:find_linters_for_filetype(ft)
        end,
        is_configured = function(ft)
            local lint = require("lint")
            local configured = lint.linters_by_ft[ft]
            return configured and #configured > 0
        end,
        configure = function(entry, ft)
            local lint = require("lint")
            lint.linters_by_ft[ft] = { entry.tool }
        end,
    })

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

    -- Auto-detection: trigger if no linter is configured
    if not has_configured_linter then
        self.auto:trigger(ft)
    end
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

function M:dump_session(choices, lines)
    if not choices["Linter"] then
        return
    end

    local linters = {}
    for ft, entry in pairs(choices["Linter"]) do
        linters[ft] = entry.tool
    end

    if not vim.tbl_isempty(linters) then
        table.insert(lines, "linters = {")
        local fts = vim.tbl_keys(linters)
        table.sort(fts)
        for _, ft in ipairs(fts) do
            table.insert(lines, ('    %s = "%s",'):format(ft, linters[ft]))
        end
        table.insert(lines, "},")
    end
end

return M

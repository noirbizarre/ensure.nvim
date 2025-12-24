local Plugin = require("ensure.plugin")
local mason = require("ensure.plugin.mason")
local util = require("ensure.util")

---@class ensure.LintPlugin : ensure.Plugin
local M = Plugin:new()

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
    if self.is_installed then
        local lint = require("lint")
        for ft, linters in pairs(opts.linters) do
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

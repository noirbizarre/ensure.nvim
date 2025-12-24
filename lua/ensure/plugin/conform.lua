local Plugin = require("ensure.plugin")
local mason = require("ensure.plugin.mason")
local util = require("ensure.util")

---@class ensure.ConformPlugin : ensure.Plugin
local M = Plugin:new()

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

function M:setup(opts)
    self.is_installed, _ = pcall(require, "conform")
    if not self.is_installed then
        return
    end

    local conform = require("conform")
    for ft, formatters in pairs(opts.formatters) do
        conform.formatters_by_ft[ft] = util.string_list(formatters)
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

function M:autoinstall(_)
    if not self.is_installed or not mason.is_enabled then
        return
    end

    local conform = require("conform")
    local bufnr = vim.api.nvim_get_current_buf()
    local formatters = conform.list_formatters_for_buffer(bufnr)

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

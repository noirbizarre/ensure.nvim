local Plugin = require("ensure.plugin")

---@class ensure.TreesitterPlugin : ensure.Plugin
local M = Plugin:new()

function M:setup(opts)
    self.is_installed, _ = pcall(require, "nvim-treesitter")
    if not self.is_installed then
        return
    end

    local parsers = opts.parsers or {}
    -- Extract parser list (array part) and auto setting
    -- Supports: { "lua", "python" }, { auto = false }, or { "lua", "python", auto = false }
    self.parsers = vim.iter(ipairs(parsers))
        :map(function(_, v)
            return v
        end)
        :totable()
    self.auto = parsers.auto ~= false -- Default to true
    self.ignore = opts.ignore.parsers

    -- Defer parser installation to avoid blocking startup
    if self.auto then
        vim.schedule(function()
            self:install()
        end)
    end
end

function M:health()
    if self.is_installed then
        vim.health.ok("`nvim-treesitter` is installed")
    else
        vim.health.error("`nvim-treesitter` is not installed")
        return
    end
    local ts = require("nvim-treesitter")
    if ts.install ~= nil then
        vim.health.ok("Using `main` branch of `nvim-treesitter`")
    else
        vim.health.error("Using `master` branch of `nvim-treesitter`, `main` branch is required")
    end
end

---Autocommand callback installing missing parser for the current filetype
function M:autoinstall(ft)
    if self.is_installed then
        local ts = require("nvim-treesitter")
        if not vim.list_contains(self.ignore, ft) and vim.list_contains(ts.get_available(), ft) then
            ts.install({ ft })
        end
    end
end

M.command = "parsers"

function M:install(opts)
    if self.is_installed then
        local ts = require("nvim-treesitter")
        local to_install = {}
        local installed = ts.get_installed("parsers")

        local candidates = self.parsers or {}
        if opts and opts.all then
            candidates = vim.list_extend(ts.get_available(1), ts.get_available(2))
        end

        for _, lang in pairs(candidates) do
            if lang and not (vim.tbl_contains(self.ignore, lang) or vim.tbl_contains(installed, lang)) then
                table.insert(to_install, lang)
            end
        end
        ts.install(to_install)
    end
end

return M

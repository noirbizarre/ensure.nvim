-- Import AutoConfig type from ensure.auto module
-- ensure.AutoConfig and ensure.Auto are defined there

-- Semantic aliases for documentation purposes
---@alias LspAuto ensure.Auto Auto-detection config for LSP servers
---@alias ToolAuto ensure.Auto Auto-detection config for formatters/linters

---@class LspConfig: {[string]: table|function}
---@field enable string[] List of LSP server names to ensure are installed via mason.nvim and enabled
---@field disable string[] List of LSP server names to ensure are not enabled (allow by-project disabling)
---@field auto LspAuto Auto-detection config: boolean or table with enable/ignore/multi fields
---@field clear boolean When true, disable all previously enabled LSPs and clear their configs (default: false)

---@class FormattersConfig: {[string]: string|string[]}
---@field auto ToolAuto Auto-detection config: boolean or table with enable/ignore/multi fields
---@field clear boolean When true, clear all previously configured formatters by filetype (default: false)

---@class LintersConfig: {[string]: string|string[]}
---@field auto ToolAuto Auto-detection config: boolean or table with enable/ignore/multi fields
---@field clear boolean When true, clear all previously configured linters by filetype (default: false)

---@class IgnoreConfig
---@field packages string[] List of package names to ignore when ensuring installation via mason.nvim
---@field parsers string[] List of treesitter parsers to ignore when ensuring installation

---@class ParsersConfig
---@field auto boolean Whether to auto-install parsers on startup (default: true)

---@class ensure.Config
---@field install boolean Force installing everything on start
---@field autocmd boolean Create BufRead/BufNewFile autoinstall autocmd
---@field packages table List of package names to ensure are installed via mason.nvim
---@field parsers ParsersConfig|string[] Treesitter parsers config or list of parsers to ensure are installed
---@field linters LintersConfig Linters by filetype with optional auto config
---@field formatters FormattersConfig Formatters by filetype with optional auto config
---@field lsp LspConfig Configuration for LSP servers
---@field ignore IgnoreConfig Configuration for ignoring certain packages or parsers
---@field plugins string[] List of plugin to load

---@class (partial) ensure.SetupOpts : ensure.Config

---@type ensure.Config
local defaults = {
    install = false,
    autocmd = true,
    packages = {},
    parsers = {
        auto = true,
    },
    formatters = {
        auto = false,
        clear = false,
    },
    linters = {
        auto = false,
        clear = false,
    },
    lsp = {
        enable = {},
        disable = {},
        auto = false,
        clear = false,
    },
    ignore = {
        packages = {},
        parsers = {},
    },
    plugins = {
        "ensure.plugin.mason",
        "ensure.plugin.lsp",
        "ensure.plugin.treesitter",
        "ensure.plugin.conform",
        "ensure.plugin.lint",
    },
}

local config = vim.deepcopy(defaults) --[[@as ensure.Config]]

local M = {}

---@param opts? ensure.SetupOpts
---@return ensure.Config
function M.setup(opts)
    config = vim.tbl_deep_extend("force", {}, vim.deepcopy(defaults), opts or {})
    return config
end

---Give the list of enabled plugins
---@return string[]
function M.get_plugins()
    return config.plugins
end
return M

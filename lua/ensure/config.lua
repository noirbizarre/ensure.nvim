---@class LspConfig: {[string]: table}
---@field enable? string[] List of LSP server names to ensure are installed via mason.nvim and enabled
---@field disable? string[] List of LSP server names to ensure are not enabled (allow by-project disabling)
---@field config? table<string, table> LSP server configurations

---@class IgnoreConfig
---@field packages? string[] List of package names to ignore when ensuring installation via mason.nvim
---@field parsers? string[] List of treesitter parsers to ignore when ensuring installation

---@class ensure.Config
---@field install? boolean Force installing everything on start
---@field packages? table List of package names to ensure are installed via mason.nvim
---@field parsers? string[] List of treesitter parsers to ensure are installed
---@field linters? table<string, string[]> Linters by filetype
---@field formatters? table<string, string[]> Formatters by filetype
---@field lsp? LspConfig Configuration for LSP servers
---@field ignore? IgnoreConfig Configuration for ignoring certain packages or parsers
---@field plugins? string[] List of plugin to load

---@type ensure.Config
local defaults = {
    install = false,
	packages = {},
	parsers = {},
    formatters = {},
    linters = {},
	lsp = {
		enable = {},
		disable = {},
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

---@param opts? ensure.Config
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

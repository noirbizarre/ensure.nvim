local Plugin = require("ensure.plugin")
local mason = require("ensure.plugin.mason")
local notify = require("ensure.notify")

---@class ensure.LspPlugin : ensure.Plugin
local M = Plugin:new()

local CONFIG_KEYS = { "enable", "disable" }

---Map of LSP names to their Mason package names (if different)
---@type table<string, string>
M.lsp_to_mason = {}

---Map of Mason packages names to their LSP names (if different)
---@type table<string, string>
M.mason_to_lsp = {}

function M:setup(opts)
    local to_enable = {}
    for _, lsp in pairs(opts.lsp.enable) do
        if not vim.list_contains(opts.lsp.disable, lsp) then
            table.insert(to_enable, lsp)
        end
    end
    vim.lsp.enable(to_enable)

    for name, config in pairs(opts.lsp) do
        if not vim.list_contains(CONFIG_KEYS, name) then
            if type(config) == "function" then
                config = config()
            end
            vim.lsp.config(name, config)
        end
    end

    if mason.is_enabled then
        -- Update the LSP <> Mason package mappings on Mason updates
        local Registry = require("mason-registry")
        self:build_mapping()
        Registry:on("update:success", function()
            self:build_mapping()
        end)
    end
end

function M:health()
    if vim.fn.has("nvim-0.11.0") == 1 then
        vim.health.ok("Using `Neovim >= 0.11.0`")
    else
        vim.health.error("`Neovim >= 0.11.0` is required")
        return
    end

    if require("ensure.mason").is_enabled then
        vim.health.ok("`ensure.mason` plugin is enabled")
    else
        vim.health.error("`ensure.mason` plugin is not enabled, LSPs won't be installed")
    end
end

function M:autoinstall(ft)
    if mason.is_enabled then
        local packages = {}

        --- List required LSP packages for this filetype
        for lsp, config in pairs(vim.lsp._enabled_configs) do
            if
                config.resolved_config
                and config.resolved_config.filetypes
                and vim.list_contains(config.resolved_config.filetypes, ft)
            then
                local package = self.lsp_to_mason[lsp] or lsp
                table.insert(packages, package)
            end
        end

        mason:install_packages(packages, function(package)
            -- Restart the LSP for the current buffer if it was just installed
            local lsp = self.mason_to_lsp[package] or package
            vim.lsp.enable(lsp, false)
            vim.lsp.enable(lsp, true)
        end)
    end
end

---Build the mapping between lspconfig names and Mason package names
function M:build_mapping()
    local Registry = require("mason-registry")
    local specs = Registry.get_all_package_specs()
    self.mason_to_lsp = {}
    self.lsp_to_mason = {}
    for _, spec in ipairs(specs) do
        local lspconfig = vim.tbl_get(spec, "neovim", "lspconfig")
        if lspconfig then
            self.lsp_to_mason[lspconfig] = spec.name
            self.mason_to_lsp[spec.name] = lspconfig
        end
    end
end

M.command = "lsps"

function M:install(opts)
    if mason.is_enabled then
        local packages = {}
        if opts and opts.all then
            --- Install all configured LSP servers
            ---@diagnostic disable-next-line: invisible
            for lsp, _ in pairs(vim.lsp.config._configs) do
                local package = self.lsp_to_mason[lsp] or lsp
                table.insert(packages, package)
            end
        else
            --- List required LSP packages for this filetype
            for lsp, _ in pairs(vim.lsp._enabled_configs) do
                local package = self.lsp_to_mason[lsp] or lsp
                table.insert(packages, package)
            end
        end

        notify("Installing LSP servers...")

        mason:install_packages(packages, function(package)
            -- Restart the LSP for the current buffer if it was just installed
            local lsp = self.mason_to_lsp[package] or package
            vim.lsp.enable(lsp, false)
            vim.lsp.enable(lsp, true)
        end)
    end
end

return M

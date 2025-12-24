local Plugin = require("ensure.plugin")
local mason = require("ensure.plugin.mason")

---@class ensure.LspPlugin : ensure.Plugin
local M = Plugin:new()

local CONFIG_KEYS = { "enable", "disable" }

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

function M:setup(opts)
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

    --- List required LSP packages for this filetype
    for lsp, config in pairs(vim.lsp._enabled_configs) do
        if
            config.resolved_config
            and config.resolved_config.filetypes
            and vim.list_contains(config.resolved_config.filetypes, ft)
        then
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

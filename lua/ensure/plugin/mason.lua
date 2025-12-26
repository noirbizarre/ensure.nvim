local Plugin = require("ensure.plugin")
local notify = require("ensure.notify")
local util = require("ensure.util")

---@class ensure.MasonPlugin : ensure.Plugin
local M = Plugin:new()

---Cached mapping from tool/executable names to Mason package names
---@type table<string, string>|nil
M._tool_to_package = nil

---Map of LSP names to their Mason package names
---@type table<string, string>|nil
M._lsp_to_mason = nil

---Map of Mason package names to their LSP names
---@type table<string, string>|nil
M._mason_to_lsp = nil

---Map of filetypes to available tools (formatters/linters) from Mason
---Structure: { [filetype] = { { tool = "tool_name", package = "package_name", categories = {...} }, ... } }
---@type table<string, {tool: string, package: string, categories: string[]}[]>|nil
M._tools_by_filetype = nil

---Whether mappings are currently being built (for async build)
---@type boolean
M._building_mappings = false

---Callbacks waiting for mappings to be built
---@type function[]
M._mapping_callbacks = {}

function M:setup(opts)
    self.packages = opts.packages
    self.ignore = opts.ignore.packages
    self.is_installed, _ = pcall(require, "mason")
    self.is_enabled = self.is_installed
        and vim.list_contains(require("ensure.config").get_plugins(), "ensure.plugin.mason")

    if self.is_enabled then
        -- Defer package checking and installation to avoid blocking startup
        vim.schedule(function()
            local Registry = require("mason-registry")
            local packages = vim.tbl_filter(function(p)
                return type(p) == "string" and not (vim.list_contains(self.ignore, p) or Registry.is_installed(p))
            end, self.packages)

            self:install_packages(packages)

            -- Clear cached mappings when registry is updated so they get rebuilt
            Registry:on("update:success", function()
                self:clear_mappings()
            end)
        end)
    end
end

---Packages which installation failed (avoid trying to install them multiple times)
---@type string[]
M.failed = {}

function M:health()
    if self.is_installed then
        vim.health.ok("`Mason` is installed")
    else
        vim.health.error("`Mason` is not installed")
        return
    end
    if require("mason.version").MAJOR_VERSION == 2 then
        vim.health.ok("`Mason` version is `2.x`")
    else
        vim.health.error("`Mason` version is not `2.x`")
    end
end

---Install packages using Mason
---@param packages string[] Packages to install using Mason
---@param callback? fun(package: string) An optional callback to run after installation
function M:install_packages(packages, callback)
    if not self.is_enabled or #packages == 0 then
        return
    end

    for _, package in pairs(packages) do
        if not vim.list_contains(self.ignore, package) then
            self:try_install(package, callback)
        end
    end
end

---Attempt to install a package using Mason
---@param package string Package to install using Mason
---@param callback? fun(package: string) An optional callback to run after installation
function M:try_install(package, callback)
    local Registry = require("mason-registry")
    local Package = require("mason-core.package")
    local package_name, version = Package.Parse(package)

    if vim.list_contains(M.failed, package) then
        return
    end

    -- If already installed, call callback immediately and return
    if Registry.is_installed(package_name) then
        if callback then
            callback(package_name)
        end
        return
    end

    local resolved = self:resolve(package_name)

    if resolved == nil then
        notify(
            (
                "Package `%q` cannot be resolved into a Mason package. "
                .. "Make sure to only provide valid package names."
            ):format(package),
            vim.log.levels.WARN
        )
        return
    end

    if not (resolved:is_installing() or resolved:is_installed()) then
        self:install_package(resolved, version, callback)
    elseif resolved:is_installing() and callback then
        resolved:once(
            "closed",
            vim.schedule_wrap(function()
                if resolved:is_installed() then
                    callback(resolved.name)
                end
            end)
        )
    end
end

---Resolve a package name into a Mason Package
---@param package string Name of the package to install
---@return Package|nil
function M:resolve(package)
    local registry = require("mason-registry")

    local ok, pkg = pcall(registry.get_package, package)
    if ok then
        return pkg
    end
end

---@param pkg Package
---@param version? string An optional version to install (latest if not provided)
---@param callback? fun(package: string) An optional callback to run after installation
function M:install_package(pkg, version, callback)
    if version == nil then
        notify(("Installing `%s`"):format(pkg.name))
    else
        notify(("Installing `%s %s`"):format(pkg.name, version))
    end

    pkg:install({ version = version }):once(
        "closed",
        vim.schedule_wrap(function()
            if pkg:is_installed() then
                notify(("`%s` was successfully installed"):format(pkg.name))
                if callback then
                    callback(pkg.name)
                end
            else
                notify(
                    ("Failed to install `%s`. Installation logs are available in :Mason and :MasonLog"):format(pkg.name),
                    vim.log.levels.ERROR
                )
            end
        end)
    )
end

function M:autoinstall(ft)
    if self.is_enabled then
        local Registry = require("mason-registry")
        local packages = {}
        for _, package in ipairs(util.string_list(self.packages[ft] or {})) do
            if not (vim.list_contains(self.ignore, package) or Registry.is_installed(package)) then
                table.insert(packages, package)
            end
        end
        self:install_packages(packages)
    end
end

M.command = "packages"

function M:install()
    if self.is_enabled then
        local Registry = require("mason-registry")
        local packages = {}
        for _, package in pairs(self.packages) do
            if type(package) == "string" then
                table.insert(packages, package)
            else
                vim.list_extend(packages, package)
            end

            packages = vim.tbl_filter(function(p)
                return not (vim.list_contains(self.ignore, p) or Registry.is_installed(p))
            end, packages)
        end
        self:install_packages(packages)
    end
end

---Build all mappings from Mason registry specs using coroutine for non-blocking
---Builds: tool_to_package, lsp_to_mason, mason_to_lsp, tools_by_filetype
---@param callback? function Optional callback when build is complete
function M:build_mappings(callback)
    -- Already built, call callback immediately
    if self._tool_to_package then
        if callback then
            callback()
        end
        return
    end

    -- If currently building, queue the callback
    if self._building_mappings then
        if callback then
            table.insert(self._mapping_callbacks, callback)
        end
        return
    end

    self._building_mappings = true
    if callback then
        table.insert(self._mapping_callbacks, callback)
    end

    -- Initialize empty tables
    self._tool_to_package = {}
    self._lsp_to_mason = {}
    self._mason_to_lsp = {}
    self._tools_by_filetype = {}

    local Registry = require("mason-registry")
    local specs = Registry.get_all_package_specs()
    local chunk_size = 100
    local index = 1

    local function process_chunk()
        local end_index = math.min(index + chunk_size - 1, #specs)

        for i = index, end_index do
            local spec = specs[i]

            -- Build tool to package mapping from bin field
            if spec.bin then
                for tool_name, _ in pairs(spec.bin) do
                    self._tool_to_package[tool_name] = spec.name
                end
            end

            -- Build LSP mappings from neovim.lspconfig field
            local lspconfig = vim.tbl_get(spec, "neovim", "lspconfig")
            if lspconfig then
                self._lsp_to_mason[lspconfig] = spec.name
                self._mason_to_lsp[spec.name] = lspconfig
            end

            -- Build tools_by_filetype mapping from languages and categories fields
            if spec.languages and spec.categories and spec.bin then
                local dominated_categories = vim.iter(spec.categories):any(function(cat)
                    return cat == "Formatter" or cat == "Linter" or cat == "LSP"
                end)
                if dominated_categories then
                    local tool_name = next(spec.bin)
                    if tool_name then
                        for _, language in ipairs(spec.languages) do
                            local ft = language:lower()
                            if not self._tools_by_filetype[ft] then
                                self._tools_by_filetype[ft] = {}
                            end
                            table.insert(self._tools_by_filetype[ft], {
                                tool = tool_name,
                                package = spec.name,
                                categories = spec.categories,
                            })
                        end
                    end
                end
            end
        end

        index = end_index + 1

        if index <= #specs then
            -- Yield to event loop, then continue
            vim.schedule(process_chunk)
        else
            -- Done building, call all queued callbacks
            self._building_mappings = false
            local callbacks = self._mapping_callbacks
            self._mapping_callbacks = {}
            for _, cb in ipairs(callbacks) do
                cb()
            end
        end
    end

    -- Start processing (use vim.schedule to not block current execution)
    vim.schedule(process_chunk)
end

---Build mappings synchronously (for when immediate result is needed)
---Prefer build_mappings() with callback when possible
function M:build_mappings_sync()
    if self._tool_to_package then
        return
    end

    self._tool_to_package = {}
    self._lsp_to_mason = {}
    self._mason_to_lsp = {}
    self._tools_by_filetype = {}

    local Registry = require("mason-registry")
    local specs = Registry.get_all_package_specs()

    for _, spec in ipairs(specs) do
        -- Build tool to package mapping from bin field
        if spec.bin then
            for tool_name, _ in pairs(spec.bin) do
                self._tool_to_package[tool_name] = spec.name
            end
        end

        -- Build LSP mappings from neovim.lspconfig field
        local lspconfig = vim.tbl_get(spec, "neovim", "lspconfig")
        if lspconfig then
            self._lsp_to_mason[lspconfig] = spec.name
            self._mason_to_lsp[spec.name] = lspconfig
        end

        -- Build tools_by_filetype mapping from languages and categories fields
        if spec.languages and spec.categories and spec.bin then
            local dominated_categories = vim.iter(spec.categories):any(function(cat)
                return cat == "Formatter" or cat == "Linter" or cat == "LSP"
            end)
            if dominated_categories then
                local tool_name = next(spec.bin)
                if tool_name then
                    for _, language in ipairs(spec.languages) do
                        local ft = language:lower()
                        if not self._tools_by_filetype[ft] then
                            self._tools_by_filetype[ft] = {}
                        end
                        table.insert(self._tools_by_filetype[ft], {
                            tool = tool_name,
                            package = spec.name,
                            categories = spec.categories,
                        })
                    end
                end
            end
        end
    end
end

---Clear all cached mappings (used when registry is updated)
function M:clear_mappings()
    self._tool_to_package = nil
    self._lsp_to_mason = nil
    self._mason_to_lsp = nil
    self._tools_by_filetype = nil
    self._building_mappings = false
    self._mapping_callbacks = {}
end

---Resolve a tool name to a Mason package name
---Returns nil if the tool is not found in Mason registry
---@param tool_name string The tool/executable name
---@return string|nil
function M:resolve_tool(tool_name)
    self:build_mappings_sync()
    return self._tool_to_package[tool_name]
end

---Resolve an LSP server name to a Mason package name
---Returns nil if the LSP is not found in Mason registry
---@param lsp_name string The LSP server name
---@return string|nil
function M:resolve_lsp(lsp_name)
    self:build_mappings_sync()
    return self._lsp_to_mason[lsp_name]
end

---Resolve a Mason package name to an LSP server name
---Returns nil if the package is not found
---@param package_name string The Mason package name
---@return string|nil
function M:lsp_from_package(package_name)
    self:build_mappings_sync()
    return self._mason_to_lsp[package_name]
end

---Find available LSPs for a filetype from Mason registry
---Returns LSPs that have configurations with matching filetypes and are available in Mason
---Uses vim.lsp.config[name] to trigger lazy-loading of LSP configs from runtime path
---@param ft string The filetype to search for
---@return ensure.AutoEntry[] List of available LSP entries
function M:find_lsps_for_filetype(ft)
    self:build_mappings_sync()
    local results = {}

    for lsp_name, package_name in pairs(self._lsp_to_mason or {}) do
        -- Use vim.lsp.config[lsp_name] to trigger lazy-loading from lsp/*.lua runtime files
        -- This ensures we find LSPs even if they haven't been explicitly configured
        local ok, config = pcall(function()
            return vim.lsp.config[lsp_name]
        end)
        if ok and config and config.filetypes and vim.list_contains(config.filetypes, ft) then
            table.insert(results, {
                tool = lsp_name,
                package = package_name,
            })
        end
    end

    return results
end

---Find available formatters for a filetype from Mason registry
---Returns formatters that have the "Formatter" category and matching language
---@param ft string The filetype to search for
---@return ensure.AutoEntry[] List of available formatter entries
function M:find_formatters_for_filetype(ft)
    self:build_mappings_sync()
    local results = {}

    local tools = self._tools_by_filetype[ft] or {}
    for _, entry in ipairs(tools) do
        if vim.list_contains(entry.categories, "Formatter") then
            table.insert(results, {
                tool = entry.tool,
                package = entry.package,
            })
        end
    end

    return results
end

---Find available linters for a filetype from Mason registry
---Returns linters that have the "Linter" category and matching language
---@param ft string The filetype to search for
---@return ensure.AutoEntry[] List of available linter entries
function M:find_linters_for_filetype(ft)
    self:build_mappings_sync()
    local results = {}

    local tools = self._tools_by_filetype[ft] or {}
    for _, entry in ipairs(tools) do
        if vim.list_contains(entry.categories, "Linter") then
            table.insert(results, {
                tool = entry.tool,
                package = entry.package,
            })
        end
    end

    return results
end

return M

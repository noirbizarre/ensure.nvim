local Plugin = require("ensure.plugin")
local notify = require("ensure.notify")
local util = require("ensure.util")

---@class ensure.MasonPlugin : ensure.Plugin
local M = Plugin:new()

---Cached mapping from tool/executable names to Mason package names
---@type table<string, string>|nil
M._tool_to_package = nil

function M:setup(opts)
    self.packages = opts.packages
    self.ignore = opts.ignore.packages
    self.is_installed, _ = pcall(require, "mason")
    self.is_enabled = self.is_installed
        and vim.list_contains(require("ensure.config").get_plugins(), "ensure.plugin.mason")

    if self.is_enabled then
        local Registry = require("mason-registry")
        local packages = vim.tbl_filter(function(p)
            return type(p) == "string" and not (vim.list_contains(self.ignore, p) or Registry.is_installed(p))
        end, self.packages)

        self:install_packages(packages)
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

    if vim.list_contains(M.failed, package) or Registry.is_installed(package_name) then
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

---Build a mapping from tool/executable names to Mason package names
---Uses the `bin` field from Mason package specs
---@return table<string, string>
function M:build_tool_mapping()
    if self._tool_to_package then
        return self._tool_to_package
    end

    self._tool_to_package = {}

    local Registry = require("mason-registry")
    local specs = Registry.get_all_package_specs()

    for _, spec in ipairs(specs) do
        if spec.bin then
            for tool_name, _ in pairs(spec.bin) do
                self._tool_to_package[tool_name] = spec.name
            end
        end
    end

    return self._tool_to_package
end

---Resolve a tool name to a Mason package name
---Returns nil if the tool is not found in Mason registry
---@param tool_name string The tool/executable name
---@return string|nil
function M:resolve_tool(tool_name)
    local mapping = self:build_tool_mapping()
    return mapping[tool_name]
end

return M

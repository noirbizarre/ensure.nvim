local Plugin = require("ensure.plugin")
local mason = require("ensure.plugin.mason")
local util = require("ensure.util")

---@class ensure.ConformPlugin : ensure.Plugin
local M = Plugin:new()

---Mapper from conform formatter names to mason package names
---Only contains formatters which name differs from mason package name
---See: https://mason-registry.dev/registry/list
---@type table<string, string>
M.mapping = {
    bsfmt = "brighterscript-formatter",
    cmake_format = "cmakelang",
    dcm_fix = "dcm",
    dcm_format = "dcm",
    deno_fmt = "deno",
    elm_format = "elm-format",
    erb_format = "erb-formatter",
    hcl = "hclfmt",
    lua_format = "luaformatter",
    nixpkgs_fmt = "nixpkgs-fmt",
    nomad_fmt = "nomad",
    opa_fmt = "opa",
    php_cs_fixer = "php-cs-fixer",
    ["purs-tidy"] = "purescript-tidy",
    ruff_fix = "ruff",
    ruff_format = "ruff",
    ruff_organize_imports = "ruff",
    sql_formatter = "sql-formatter",
    terraform_fmt = "terraform",
}

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
    local conform = require("conform")

    if mason.is_enabled then
        local formatters = conform.list_formatters_for_buffer(vim.api.nvim_get_current_buf())
        if formatters then
            local packages = {}
            for _, formatter in ipairs(formatters) do
                table.insert(packages, M.mapping[formatter] or formatter)
            end
            mason:install_packages(packages)
        end
    end
end

M.command = "formatters"

function M:install()
    if self.is_installed and mason.is_enabled then
        local conform = require("conform")
        local packages = {}
        local known_formatters = vim.tbl_keys(require("conform.formatters").list_all_formatters())
        for _, info in pairs(conform.list_all_formatters()) do
            ---Only install known linters
            if vim.tbl_contains(known_formatters, info.name) then
                table.insert(packages, M.mapping[info.name] or info.name)
            end
        end
        mason:install_packages(packages)
    end
end

return M

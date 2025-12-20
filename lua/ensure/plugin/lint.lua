local Plugin = require("ensure.plugin")
local mason = require("ensure.plugin.mason")
local notify = require("ensure.notify")

---@class ensure.LintPlugin : ensure.Plugin
local M = Plugin:new()

---Mapping from `nvim-lint` linters to Mason package names
---Only contains linters which name differs from mason package name
---See: https://mason-registry.dev/registry/list
---@type table<string, string>
M.mapping = {
    ansible_lint = "ansible-lint",
    buf_lint = "buf",
    cfn_lint = "cfn-lint",
    clj_kondo = "clj-kondo",
    erb_lint = "erb-lint",
    gdlint = "gdtoolkit",
    golangcilint = "golangci-lint",
    snyk_iac = "snyk",
    write_good = "write-good",
}

function M:setup(opts)
    self.is_installed, _ = pcall(require, "lint")
    if self.is_installed then
        local lint = require("lint")
        for ft, linters in pairs(opts.linters) do
            lint.linters_by_ft[ft] = linters
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
    if self.is_installed and mason.is_enabled then
        local lint = require("lint")
        local linters = lint._resolve_linter_by_ft(ft)
        if linters then
            local packages = {}
            for _, linter in ipairs(linters) do
                table.insert(packages, M.mapping[linter] or linter)
            end
            mason:install_packages(packages)
        end
    end
end

M.command = "linters"

function M:install()
    if self.is_installed and mason.is_enabled then
        local lint = require("lint")
        local packages = {}
        for _, linters in pairs(lint.linters_by_ft) do
            for _, linter in ipairs(linters) do
                table.insert(packages, M.mapping[linter] or linter)
            end
        end
        mason:install_packages(packages)
    end
end

return M

local M = {}

M.check = function()
    vim.health.start("ensure")

    local has_lazy, _ = pcall(require, "lazy")
    if has_lazy then
        vim.health.ok("`lazy.nvim` is installed")
    else
        vim.health.warn("`lazy.nvim` is not installed, `opts` merging not available")
    end

    local plugins = require("ensure.config").get_plugins()

    for _, name in pairs(plugins) do
        vim.health.start(name)
        local plugin = require(name) --[[@as ensure.Plugin]]
        plugin:health()
    end
end

return M

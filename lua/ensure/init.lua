local M = {}

---@param opts ensure.Config
function M.setup(opts)
    local config = require("ensure.config").setup(opts)
    for _, name in pairs(config.plugins) do
        local plugin = require(name) --[[@as ensure.Plugin]]
        plugin:setup(config)
    end
    require("ensure.command")

    vim.api.nvim_create_autocmd({"BufNewFile", "BufRead"}, {
        group = vim.api.nvim_create_augroup("ensure", {}),
        pattern = "*",
        callback = M.autoinstall,
        desc = "Ensure: Auto install missing packages for the current buffer",
    })

    vim.api.nvim_create_user_command("Ensure", require("ensure.command"), {
        desc = "Ensure dependencies are installed",
        nargs = "?",
        bang = true,
    })

    if opts.install then
        M.install()
    end
end

---Install declared packages/dependencies
---@param opts? ensure.CommandOpts
function M.install(opts)
    for _, name in pairs(require("ensure.config").get_plugins()) do
        local plugin = require(name) --[[@as ensure.Plugin]]
        plugin:install(opts)
    end
end

--- Install all packages required for the current buffer
function M.autoinstall()
    local ft = vim.bo.filetype
    if not ft or ft == "" then
        return
    end

    for _, name in pairs(require("ensure.config").get_plugins()) do
        local plugin = require(name) --[[@as ensure.Plugin]]
        plugin:autoinstall(ft)
    end
end

return M

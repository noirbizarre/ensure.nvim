local notify = require("ensure.notify")

---@class ensure.CommandOpts
---@field all boolean Whether to install all plugins

---The `Ensure` command callback.
---@param opts vim.api.keyset.create_user_command.command_args
return function(opts)
    ---@type ensure.CommandOpts
    local params = {all = opts.bang}

    if #opts.fargs == 0 then
        require("ensure").install(params)
    else
        local subcommands = {}
        for _, name in pairs(require("ensure.config").get_plugins()) do
            local plugin = require(name) --[[@as ensure.Plugin]]
            if plugin.command then
                subcommands[plugin.command] = plugin
            end
        end

        local plugin = subcommands[opts.fargs[1]]
        if plugin then
            plugin:install(params)
        else
            local available = vim.tbl_keys(subcommands)
            table.sort(available)
            notify(
                "Unknown argument: `"
                    .. (opts.fargs[1] or "nil")
                    .. "`\n"
                    .. "Must be one of [all, install, "
                    .. table.concat(available, ", ")
                    .. "].",
                vim.log.levels.ERROR
            )
        end
    end
end

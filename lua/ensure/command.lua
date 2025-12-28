local auto = require("ensure.auto")
local notify = require("ensure.notify")

---@class ensure.CommandOpts
---@field all boolean Whether to install all plugins

---Session subcommands
local session_commands = {
    ---Clear all session choices
    clear = function()
        auto.clear_session_choices()
        notify("Session choices cleared")
    end,

    ---Dump session choices as configuration
    dump = function()
        local choices = auto.get_session_choices()
        if vim.tbl_isempty(choices) then
            notify("No session choices to dump", vim.log.levels.WARN)
            return
        end

        local lines = { "-- Add to your ensure.nvim configuration:" }

        -- Process LSP servers
        if choices["LSP server"] then
            local servers = {}
            for _, entry in pairs(choices["LSP server"]) do
                table.insert(servers, entry.tool)
            end
            if #servers > 0 then
                table.sort(servers)
                table.insert(lines, "lsp = {")
                table.insert(lines, ('    enable = { "%s" },'):format(table.concat(servers, '", "')))
                table.insert(lines, "},")
            end
        end

        -- Process Formatters
        if choices["Formatter"] then
            local formatters = {}
            for ft, entry in pairs(choices["Formatter"]) do
                formatters[ft] = entry.tool
            end
            if not vim.tbl_isempty(formatters) then
                table.insert(lines, "formatters = {")
                local fts = vim.tbl_keys(formatters)
                table.sort(fts)
                for _, ft in ipairs(fts) do
                    table.insert(lines, ('    %s = "%s",'):format(ft, formatters[ft]))
                end
                table.insert(lines, "},")
            end
        end

        -- Process Linters
        if choices["Linter"] then
            local linters = {}
            for ft, entry in pairs(choices["Linter"]) do
                linters[ft] = entry.tool
            end
            if not vim.tbl_isempty(linters) then
                table.insert(lines, "linters = {")
                local fts = vim.tbl_keys(linters)
                table.sort(fts)
                for _, ft in ipairs(fts) do
                    table.insert(lines, ('    %s = "%s",'):format(ft, linters[ft]))
                end
                table.insert(lines, "},")
            end
        end

        if #lines == 1 then
            notify("No session choices to dump", vim.log.levels.WARN)
            return
        end

        -- Output the configuration
        notify(table.concat(lines, "\n"))
    end,
}

---The `Ensure` command callback.
---@param opts vim.api.keyset.create_user_command.command_args
return function(opts)
    ---@type ensure.CommandOpts
    local params = { all = opts.bang }

    if #opts.fargs == 0 then
        require("ensure").install(params)
    elseif opts.fargs[1] == "session" then
        -- Handle session subcommands
        local subcmd = opts.fargs[2]
        if subcmd and session_commands[subcmd] then
            session_commands[subcmd]()
        else
            local available = vim.tbl_keys(session_commands)
            table.sort(available)
            notify(
                "Unknown session subcommand: `"
                    .. (subcmd or "nil")
                    .. "`\n"
                    .. "Must be one of ["
                    .. table.concat(available, ", ")
                    .. "].",
                vim.log.levels.ERROR
            )
        end
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
            table.insert(available, "session")
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

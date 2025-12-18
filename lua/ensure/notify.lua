
---Dispatch a notification
---@param msg string The notification message
---@param level? vim.log.levels The log level
return function(msg, level)
    level = level or vim.log.levels.INFO
	vim.notify(msg, level, {title = "ensure.nvim"})
end

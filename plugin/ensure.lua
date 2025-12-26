-- Lazy-loaded: only setup if the module was explicitly required by user config
-- This allows lazy.nvim and other plugin managers to control the loading
if package.loaded["ensure"] then
    require("ensure")
end

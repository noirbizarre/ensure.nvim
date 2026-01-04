local helpers = require("spec.helpers")
local match = require("luassert.match")

describe("ensure.init", function()
    after_each(function()
        helpers.teardown()
    end)

    local ensure = require("ensure")
    local config = require("ensure.config")

    it("calls setup on all configured plugins", function()
        local orig_setup = config.setup
        local cfg

        helpers.stub(config, "setup", function(opts)
            cfg = orig_setup(opts)
            return cfg
        end)

        local plugin1 = helpers.plugin("plugin.one")
        local plugin2 = helpers.plugin("plugin.two")

        ensure.setup({ plugins = { "plugin.one", "plugin.two" } })

        assert.stub(plugin1.methods.setup).was_called_with(match.is_ref(plugin1), cfg)
        assert.stub(plugin2.methods.setup).was_called_with(match.is_ref(plugin2), cfg)
    end)

    it("registers autocommands and user command", function()
        helpers.stub(vim.api, "nvim_create_autocmd")
        helpers.stub(vim.api, "nvim_create_user_command")

        ensure.setup({})

        assert
            .stub(vim.api.nvim_create_autocmd)
            .was_called_with({ "BufNewFile", "BufRead" }, match.table_with({ pattern = "*", callback = ensure.autoinstall }))
        assert
            .stub(vim.api.nvim_create_user_command)
            .was_called_with("Ensure", match.is_function(), match.table_with({ nargs = "*", bang = true }))
    end)

    it("calls install when opts.install is true", function()
        helpers.stub(ensure, "install")

        ensure.setup({ install = true, plugins = {} })

        assert.stub(ensure.install).was_called_with()
    end)

    it("install calls install on all plugins", function()
        helpers.stub(config, "get_plugins", { "plugin.install" })

        local plugin = helpers.plugin("plugin.install")

        ensure.install({ all = true })

        assert.stub(plugin.methods.install).was_called_with(match.is_ref(plugin), match.is_table())
    end)

    it("autoinstall returns early when filetype is empty", function()
        vim.bo.filetype = ""
        helpers.stub(config, "get_plugins", { "plugin.one" })
        local plugin = helpers.plugin("plugin.one")

        ensure.autoinstall()

        assert.stub(plugin.methods.autoinstall).was_not_called()
    end)

    it("autoinstall calls autoinstall on all plugins with filetype", function()
        vim.bo.filetype = "lua"
        helpers.stub(config, "get_plugins", { "plugin.one", "plugin.two" })
        local plugin1 = helpers.plugin("plugin.one")
        local plugin2 = helpers.plugin("plugin.two")

        ensure.autoinstall()

        assert.stub(plugin1.methods.autoinstall).was_called_with(match.is_ref(plugin1), "lua")
        assert.stub(plugin2.methods.autoinstall).was_called_with(match.is_ref(plugin2), "lua")
    end)

    it("autoinstall splits compound filetypes and calls plugins for each part", function()
        vim.bo.filetype = "html.handlebars"
        helpers.stub(config, "get_plugins", { "plugin.one" })
        local plugin = helpers.plugin("plugin.one")

        ensure.autoinstall()

        assert.stub(plugin.methods.autoinstall).was_called(2)
        assert.stub(plugin.methods.autoinstall).was_called_with(match.is_ref(plugin), "html")
        assert.stub(plugin.methods.autoinstall).was_called_with(match.is_ref(plugin), "handlebars")
    end)

    it("autoinstall handles triple compound filetypes", function()
        vim.bo.filetype = "a.b.c"
        helpers.stub(config, "get_plugins", { "plugin.one" })
        local plugin = helpers.plugin("plugin.one")

        ensure.autoinstall()

        assert.stub(plugin.methods.autoinstall).was_called(3)
        assert.stub(plugin.methods.autoinstall).was_called_with(match.is_ref(plugin), "a")
        assert.stub(plugin.methods.autoinstall).was_called_with(match.is_ref(plugin), "b")
        assert.stub(plugin.methods.autoinstall).was_called_with(match.is_ref(plugin), "c")
    end)
end)

vim.print("Loading ensure.nvim config")
return {
    "noirbizarre/ensure.nvim",
    event = "BufReadPre",
    cmd = "Ensure",
    dependencies = {
        {"mason-org/mason.nvim", optional = true},
        {"neovim/nvim-lspconfig", optional = true},
        {"nvim-treesitter/nvim-treesitter", optional = true},
        {"stevearc/conform.nvim", optional = true},
        {"mfussenegger/nvim-lint", optional = true},
    },
    ---@type ensure.SetupOpts
    opts = {},
    opts_extend = {
        "ignore.packages",
        "ignore.parsers",
        "lsp.disable",
        "lsp.enable",
        "packages",
        "parsers",
        "plugins",
    },
}

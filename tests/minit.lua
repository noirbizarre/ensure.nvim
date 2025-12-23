#!/usr/bin/env -S nvim -l

vim.env.LAZY_STDPATH = ".tests"
load(vim.fn.system("curl -s https://raw.githubusercontent.com/folke/lazy.nvim/main/bootstrap.lua"))()

-- Setup lazy.nvim
require("lazy.minit").busted({
    spec = {
        "williamboman/mason-lspconfig.nvim",
        "williamboman/mason.nvim",
        "nvim-treesitter/nvim-treesitter",
        "mfussenegger/nvim-lint",
        "stevearc/conform.nvim",
        { dir = vim.uv.cwd() },
    },
})

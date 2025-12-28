#!/usr/bin/env -S nvim -l

vim.env.LAZY_STDPATH = ".tests"
load(vim.fn.system("curl -s https://raw.githubusercontent.com/folke/lazy.nvim/main/bootstrap.lua"))()

-- Setup lazy.nvim
require("lazy.minit").busted({
    spec = {
        "mfussenegger/nvim-lint",
        "nvim-treesitter/nvim-treesitter",
        "stevearc/conform.nvim",
        "williamboman/mason.nvim",
        { dir = vim.uv.cwd() },
    },
})

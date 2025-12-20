# 📦 `ensure.nvim`

Help to modularize `lazy.nvim` based config by providing:

- A simple way to ensure Mason dependencies are installed
- filetype-based automatic tree-sitter parser installation
- LSP server installation and setup
- project-specific configuration loading

## Installation

```lua
    {
        "noirbizarre/ensure.nvim",
    }
```

All dependencies are optional as `ensure.nvim` will detect installed plugin.
But you can explicitly declare them to make sure they are installed:

```lua
    {
        "noirbizarre/ensure.nvim",
        dependencies = {
            "mason-org/mason.nvim",
            "neovim/nvim-lspconfig",
            "nvim-treesitter/nvim-treesitter",
            "stevearc/conform.nvim",
            "mfussenegger/nvim-lint",
        },
    }
```

This plugin is lazy-loaded by default.

### Configuration

Default configuration is empty and just load all provided plugins:

```lua
{
    install = false,
    --- Mason packages to install
    packages = {},
    --- Treesitter parsers to install
    parsers = {},
    --- `conform.nvim` formatters by filetypes
    formatters = {},
    --- `nvim-lint` linters by filetypes
    linters = {},
    lsp = {
        --- LSP servers to enable
        enable = {},
        --- LSP servers to disable (take precedence over `enable`)
        disable = {},
    },
    ignore = {
        --- Mason packages to ignore (never install)
        packages = {},
        --- Treesitter parsers to ignore (never install)
        parsers = {},
    },
    --- Enabled plugins
    plugins = {
        "ensure.plugin.mason",
        "ensure.plugin.lsp",
        "ensure.plugin.treesitter",
        "ensure.plugin.conform",
        "ensure.plugin.lint",
    },
}
```

## Usage

First, don't forget to run `:checkhealth ensure` to verify that all dependencies are installed and configured properly.

### Declarative base

First purpose of `ensure.nvim` is to provide a declarative way to ensure that certain dependencies are installed and configured.

The plugin declaratively ensures that the specified Mason packages are installed, tree-sitter parsers are set up, and LSP servers configured.

You can configure it once and for all:

```lua
{
    "noirbizarre/ensure.nvim",
    opts = {
        packages = {"mason", "packages", "to", "install", ft = {"package-for-filetype"}},
        parsers = {"treesitter", "parsers", "to", "install"},
        lsp = {
            enable = {"lsp", "to", "install", "and", "enable" },
            my_lsp = {
                -- lsp specific settings
            },
        },
        formatters = {
            ft = {"formatters", "for", "ft"}
        },
        linters = {
            ft = {"linters", "for", "ft"}
        },
        ignore = {
            packages = {"packages", "to", "ignore"},
            parsers = {"parsers", "to" "ignore"},
        },
    },
}
```

You can also take benefit of `lazy.nvim` `opts` merging to modularize your configuration by providing only settings related to the current module.
By default, the following list will be merged (aka. not need to declare them as `opts_extend` by yourself):

- `ignore.packages`
- `ignore.parsers`
- `lsp.disable`
- `lsp.enable`
- `packages`
- `parsers`
- `plugins`

> [!TIP]
> All filetypes entries support both a list of strings or a single string.
>
> ```lua
> {
>     "noirbizarre/ensure.nvim",
>     opts = {
>         packages = { ft = "package-for-filetype" },
>         formatters = { ft = "formatter" },
>         linters = { ft = "linters" },
>     },
> }
> 
> ```

### Install with the `Ensure` command

You can install all packages and parser with the `Ensure` command.
With the built-in plugins, it will install:

- all declared Mason `packages`
- all declared tree-sitter `parsers`
- enabled LSP servers (with the `ensure.nvim` configuration or with `vim.lsp.enable()`)
- declared `conform.nvim` formatters (with the `formatters` configuration or directly by settings `conform.formatters_by_ft`)
- declared `nvim-lint` formatters (with the `linters` configuration or directly by settings `lint.formatters_by_ft`)

> [!NOTE]
> Setting `install = true` in the options will do the same on plugin initialization.

> [!NOTE]
> You can also do it programmatically with:
> ```lua
> require('ensure').install()
> ```

The bang version `Ensure!` will install:

- all declared Mason `packages`
- all known tree-sitter `parsers`
- enabled and configured LSP servers (with the `ensure.nvim` configuration or with `vim.lsp.enable()`/`vim.lsp.configure()`)
- declared `conform.nvim` formatters (with the `formatters` configuration or directly by settings `conform.formatters_by_ft`)
- declared `nvim-lint` formatters (with the `linters` configuration or directly by settings `lint.formatters_by_ft`)

> [!NOTE]
> You can also do it programmatically with:
> ```lua
> require('ensure').install({all = true})
> ```

`ignore.packages` and `ignore.parsers` will be taken into account in both cases.

You can also call the `Ensure` and `Ensure!` commands with a specific plugin name to only install dependencies related to that plugin:

- `Ensure packages` to only install Mason packages from the `packages` setting
- `Ensure parsers` to only install Treesitter parsers
- `Ensure lsps` to only install LSP servers
- `Ensure formatters` to only install `conform.nvim` formatters
- `Ensure linters` to only install `nvim-lint` linters

### Asynchronous on-demand loading


Depending on the enabled plugins, `ensure.nvim` will automatically install missing requirements when loading a file:

- Enabled LSP servers.
- Linters.
- Formatters.
- Tree-sitter parsers.

### By project configuration

`ensure.nvim` can also override specific project configuration using a `.lazy.lua` file:

```lua
return {
    "noirbizarre/ensure.nvim",
    opts = {
        packages = {"a-mason-package"},
        lsp = {
            -- Disable the default enabled LSP and replace it with another one
            disable = {"default-lsp-server"},
            enable = {"new-lsp-server"},
        },
        linters = {
            -- Override linters for filetypes
            ft = {"a-linter-for-this-project"}
        },
        formatters = {
            -- Override formatters for filetypes
            ft = {"a-linter-for-this-project"}
        },
    },
}
```

## Plugins

`ensure.nvim` uses a plugin-based architecture to provide modular features.

It comes with the following plugins:

- `ensure.plugin.mason`: handle `Mason.nvim` packages installation.
- `ensure.plugin.treesitter`: handle `nvim-treesitter` parsers installation.
- `ensure.plugin.lsp`: handle LSP servers installation and setup.
- `ensure.plugin.conform`: handle `conform.nvim` formatters installation.
- `ensure.plugin.lint`: handle `nvim-lint` linters installation.

Each plugin implements the [`ensure.Plugin` interface](lua/ensure/plugin/init.lua) and can be enabled or disabled using the `plugins` configuration option.

You can provide your own plugins by implementing the `ensure.Plugin` interface and adding them to the `plugins` configuration option.

Here's a summary of the available plugins features:

| Plugin | `setup()` | `BufRead` | `Ensure` | `Ensure!` |
| ------ | --------- | ---------- | ------ | ------- |
| `ensure.plugin.mason` | Install `packages` | Install `packages.<filetype>` | Install `packages` (including filetypes) | Install `packages` (including filetype) |
| `ensure.plugin.treesitter` | Install `parsers` | Install missing parsers for the filetype | Install `parsers` | Install all known treesitter parsers |
| `ensure.plugin.lsp` | Enable `lsp.enable` parsers, skip `lsp.disable`, configure `lsp.*` LSPs | Install missing LSPs for the filetype | Install enabled LSP servers, skip `lsp.disable` | Install configured LSP servers |
| `ensure.plugin.conform` | Declare formatters by filetype | Install missing formatters for the filetype | Install all registered formatters | Install all registered formatters |
| `ensure.plugin.lint` | Declare linters by filetype | Install missing linters for the filetype | Install all registered linters | Install all registered linters |

## FAQ

### Why another plugin ?

I wanted a simple way to declaratively ensure that my mason dependencies, tree-sitter parsers and LSP servers are installed and configured without having to write boilerplate code in each of my `lazy.nvim` spec modules.

Plus, with the Mason 2.0 API, the Neovim 0.11 `vim.lsp` API and the `nvim-treesitter` new API, most plugins I used were broken (https://github.com/mason-org/mason-lspconfig.nvim/issues/535, https://github.com/mason-org/mason-lspconfig.nvim/issues/606) or archived (https://github.com/zapling/mason-conform.nvim).

We now have all the required API to make this work seamlessly so I decided to create this plugin.

### Is `lazy.nvim` required ?

`lazy.nvim` is not strictly required, but this plugin is designed to work seamlessly with it.
I use `lazy.nvim` as my plugin manager, and this plugin is tailored to work well within that ecosystem.

However, if you are using another plugin manager, you can still use `ensure.nvim`, but you might need to adapt some parts of the configuration to fit your setup.

You need to make sure that the dependencies are loaded before `ensure.nvim` is loaded.

- `mason-org/mason.nvim` for the Mason plugin
- `neovim/nvim-lspconfig` for the LSP plugin
- `nvim-treesitter/nvim-treesitter` for the treesitter plugin
- `stevearc/conform.nvim` for the conform plugin
- `mfussenegger/nvim-lint` for the lint plugin


Also note that those features might be exclusive to `lazy.nvim`:

- Configuration merging using `opts`: this plugin relies on `lazy.nvim`'s ability to merge options tables from multiple sources. If you are not using `lazy.nvim`, you will need to handle configuration merging manually.
- By project configuration using `.lazy.lua` only works `lazy.nvim`. (you might be able to work with `.nvim.lua` files to manually achieve the same thing)

The `Ensure` command as well as on demand installation of missing parsers/formatters/linters should work fine without `lazy.nvim`.

### Why isn't there any tests

This plugin started as a personal project to simplify my own Neovim configuration.
I use it daily, and it works well for my use case.
I plan to add tests in the future, but for now, I rely on my own usage to ensure its functionality.

## Acknowledgements

First, thanks to [@folke](https://github.com/folke) for his amazing work which made:

- this plugin possible
- my Neovim configuration so much easier to manage
- my daily Neovim experience so much better
- learn lot on Neovim and [`lazy.nvim`](https://github.com/folke/lazy.nvim) with its [dotfiles](https://github.com/folke/dot) and `LazyVim` (which I don't use but is a clear inspiration).

Thanks to all the maintainers of the plugins I depend on:

- [@stevearc](https://github.com/stevearc) for [`conform.nvim`](https://github.com/stevearc/conform.nvim#formatters)
- [@mfussenegger](https://github.com/mfussenegger) for [`nvim-lint`](https://github.com/mfussenegger/nvim-lint)
- the [@mason-org](https://github.com/mason-org/mason.nvim) team for [`mason.nvim`](https://github.com/mason-org/mason.nvim)

Thanks for the maintainers of the plugins I used as inspiration:

- [@rshkarin](https://github.com/rshkarin) for [`mason-nvim-lint`](https://github.com/rshkarin/mason-nvim-lint)
- [@zapling](https://github.com/zapling) [`mason-conform.nvim`](https://github.com/zapling/mason-conform.nvim)

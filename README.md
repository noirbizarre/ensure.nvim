# ensure.nvim

[![pre-commit.ci status](https://results.pre-commit.ci/badge/github/noirbizarre/ensure.nvim/main.svg)](https://results.pre-commit.ci/latest/github/noirbizarre/ensure.nvim/main)
[![CI](https://github.com/noirbizarre/ensure.nvim/actions/workflows/ci.yaml/badge.svg)](https://github.com/noirbizarre/ensure.nvim/actions/workflows/ci.yaml)

Declarative tool management for Neovim. Automatically install and configure LSP servers, formatters, linters, and tree-sitter parsers.

## Features

- **Automatic installation**: Tools are installed on-demand when you open a file
- **Declarative configuration**: Define what you need, let the plugin handle the rest
- **Auto-detection**: Suggest and install tools for filetypes without configuration
- **Modular**: Works with your existing Mason, LSP, conform, and nvim-lint setup
- **Project-specific**: Override configuration per-project with `.lazy.lua`

## Installation

```lua
{
    "noirbizarre/ensure.nvim",
    dependencies = {
        "mason-org/mason.nvim",         -- Required for tool installation
        -- Optional integrations:
        "nvim-treesitter/nvim-treesitter",
        "stevearc/conform.nvim",
        "mfussenegger/nvim-lint",
    },
}
```

> [!NOTE]
> If you already have Mason, LSP, Treesitter, Conform or Lint configured, `ensure.nvim` will automatically install missing tools when you open a file. No configuration needed.
> Also, if you already have the required dependencies installed, you can omit them from the `dependencies` list.

## Quick Start

### Basic Setup

```lua
{
    "noirbizarre/ensure.nvim",
    opts = {
        -- LSP servers
        lsp = {
            enable = { "lua_ls", "pyright", "ts_ls" },
        },
        -- Formatters (by filetype)
        formatters = {
            lua = "stylua",
            python = { "ruff_format", "ruff_organize_imports" },
            javascript = "prettier",
        },
        -- Linters (by filetype)
        linters = {
            python = "ruff",
            javascript = "eslint",
        },
        -- Tree-sitter parsers (array format for specific parsers)
        parsers = { "lua", "python", "javascript", "typescript" },
        -- Additional Mason packages
        packages = { "codespell" },
    },
}
```

### Auto-Detection Mode

Let `ensure.nvim` automatically find and suggest tools for filetypes you haven't configured:

```lua
{
    "noirbizarre/ensure.nvim",
    opts = {
        lsp = { auto = true },
        formatters = { auto = true },
        linters = { auto = true },
    },
}
```

When you open a file without a configured tool:
- **Single match**: Automatically installed and enabled
- **Multiple matches**: Prompts you to choose

> [!TIP]
> Auto-detection choices are persisted across sessions. If you use a session manager, ensure `globals` is included in your `sessionoptions`:
>
> ```lua
> vim.opt.sessionoptions:append("globals")
> ```

### Disabling Parser Auto-Installation

By default, tree-sitter parsers are automatically installed on startup. To disable this while still declaring which parsers you want:

```lua
{
    "noirbizarre/ensure.nvim",
    opts = {
        parsers = { "lua", "python", auto = false },
    },
}
```

### Custom Filetype-to-Parser Mappings

`ensure.nvim` automatically resolves filetypes to parser names using `vim.treesitter.language.get_lang()`. This means:

- Built-in mappings work out of the box (e.g., `sh` → `bash`, `help` → `vimdoc`, `typescriptreact` → `tsx`)
- User-registered filetypes via `vim.treesitter.language.register()` are supported

For example, if you have a custom filetype that should use an existing parser:

```lua
-- Register your custom filetype to use the python parser
vim.treesitter.language.register("python", "mycustomft")

-- ensure.nvim will automatically install the python parser when opening mycustomft files
```

### Fine-Grained Auto-Detection

```lua
{
    "noirbizarre/ensure.nvim",
    opts = {
        formatters = {
            auto = {
                enable = true,
                multi = false,  -- Don't prompt, skip if multiple options
                ignore = {
                    "prettier",                 -- Never suggest prettier
                    markdown = "*",             -- Disable auto-detection for markdown
                    javascript = { "deno_fmt" }, -- Ignore deno_fmt for javascript only
                },
            },
        },
    },
}
```

The `ignore` option supports:
- Global ignores: `{ "tool1", "tool2" }` - ignored for all filetypes
- Filetype-specific: `{ javascript = { "deno_fmt" } }` - ignored for that filetype only
- Disable filetype: `{ markdown = "*" }` - no auto-detection for that filetype
- Mixed: `{ "codespell", javascript = { "deno_fmt" }, markdown = "*" }`

#### Default Ignores

Auto-detection ignores spelling/grammar tools by default:

- **LSP**: `copilot`, `harper_ls`, `grammarly`, `ltex`, `ltex_plus`, `prosemd_lsp`, `textlsp`, `typos_lsp`, `vale_ls`
- **Formatters**: `codespell`, `misspell`, `typos`
- **Linters**: `alex`, `codespell`, `cspell`, `misspell`, `proselint`, `textlint`, `typos`, `vale`, `woke`, `write_good`

Your custom ignores are merged with these defaults.

## Modular Configuration

Take advantage of `lazy.nvim` opts merging to split configuration across files:

```lua
-- lua/plugins/python.lua
return {
    "noirbizarre/ensure.nvim",
    opts = {
        lsp = { enable = { "pyright" } },
        formatters = { python = { "ruff_format" } },
        linters = { python = "ruff" },
    },
}
```

```lua
-- lua/plugins/typescript.lua
return {
    "noirbizarre/ensure.nvim",
    opts = {
        lsp = { enable = { "ts_ls" } },
        formatters = { typescript = "prettier" },
        linters = { typescript = "eslint" },
    },
}
```

These are automatically merged. The following lists support `lazy.nvim` merging out of the box:
`packages`, `parsers`, `plugins`, `lsp.enable`, `lsp.disable`, `ignore.packages`, `ignore.parsers`

### Clearing Previous Configuration

When using modular or project-specific configuration, you may want to completely replace previous settings rather than merge with them. Use the `clear` option:

```lua
-- .lazy.lua (project-specific)
return {
    "noirbizarre/ensure.nvim",
    opts = {
        lsp = {
            clear = true,  -- Disable all previously enabled LSPs and clear their configs
            enable = { "pylsp" },  -- Only use pylsp for this project
        },
        formatters = {
            clear = true,  -- Remove all previously configured formatters
            python = "black",  -- Only use black
        },
        linters = {
            clear = true,  -- Remove all previously configured linters
            python = "pylint",  -- Only use pylint
        },
    },
}
```

The `clear` option (default: `false`):
- **`lsp.clear`**: Disables all currently enabled LSP servers and clears their configurations
- **`formatters.clear`**: Removes all entries from `conform.formatters_by_ft`
- **`linters.clear`**: Removes all entries from `lint.linters_by_ft`

This is useful when you want project-specific tooling without inheriting your global configuration.

## Commands

| Command | Description |
| ------- | ----------- |
| `Ensure` | Install all declared tools |
| `Ensure!` | Install all tools including configured but not enabled |
| `Ensure packages` | Install Mason packages only |
| `Ensure parsers` | Install tree-sitter parsers only |
| `Ensure lsps` | Install LSP servers only |
| `Ensure formatters` | Install formatters only |
| `Ensure linters` | Install linters only |
| `Ensure session clear` | Clear all auto-detection session choices |
| `Ensure session dump` | Output configuration to persist session choices |

> [!TIP]
> Set `install = true` in options to run installation on startup.

## Project-Specific Configuration

Override settings per-project using a `.lazy.lua` file in your project root:

```lua
-- .lazy.lua
return {
    "noirbizarre/ensure.nvim",
    opts = {
        lsp = {
            disable = { "pyright" },  -- Disable default LSP
            enable = { "pylsp" },     -- Use different LSP for this project
        },
        formatters = {
            python = "black",  -- Override formatter
        },
    },
}
```

## LSP Configuration

Configure LSP servers directly in `ensure.nvim`:

```lua
{
    "noirbizarre/ensure.nvim",
    opts = {
        lsp = {
            enable = { "lua_ls", "pyright" },
            disable = { "ts_ls" },  -- Takes precedence over enable
            -- Server-specific settings (passed to vim.lsp.config)
            lua_ls = {
                settings = {
                    Lua = {
                        diagnostics = { globals = { "vim" } },
                    },
                },
            },
        },
    },
}
```

## Filetype-Specific Packages

Install Mason packages only when opening specific filetypes:

```lua
{
    "noirbizarre/ensure.nvim",
    opts = {
        packages = {
            "universal-package",
            python = "debugpy",
            go = { "delve", "gofumpt" },
        },
    },
}
```

## Ignoring Tools

Prevent specific tools from being installed:

```lua
{
    "noirbizarre/ensure.nvim",
    opts = {
        ignore = {
            packages = { "some-package" },
            parsers = { "some-parser" },
        },
    },
}
```

## Health Check

Run `:checkhealth ensure` to verify your setup.

## Full Configuration Reference

```lua
{
    "noirbizarre/ensure.nvim",
    opts = {
        -- Install all tools on startup (default: false)
        install = false,

        -- Mason packages
        packages = {
            "package1",
            filetype = { "package-for-filetype" },
        },

        -- Tree-sitter parsers
        -- Can include auto = false to disable auto-installation on startup
        parsers = { "lua", "python", auto = true },

        -- LSP servers
        lsp = {
            enable = {},   -- Servers to enable
            disable = {},  -- Servers to disable (takes precedence)
            auto = false,  -- Auto-detect servers (boolean or table)
            clear = false, -- Clear all previously enabled LSPs and their configs
            -- Server configs are passed to vim.lsp.config()
            server_name = { settings = {} },
        },

        -- Formatters (conform.nvim)
        formatters = {
            auto = false,  -- Auto-detect formatters
            clear = false, -- Clear all previously configured formatters
            filetype = { "formatter1", "formatter2" },
        },

        -- Linters (nvim-lint)
        linters = {
            auto = false,  -- Auto-detect linters
            clear = false, -- Clear all previously configured linters
            filetype = { "linter1" },
        },

        -- Ignore lists
        ignore = {
            packages = {},
            parsers = {},
        },

        -- Enabled plugins
        plugins = {
            "ensure.plugin.mason",
            "ensure.plugin.lsp",
            "ensure.plugin.treesitter",
            "ensure.plugin.conform",
            "ensure.plugin.lint",
        },
    },
}
```

## FAQ

### Why another plugin?

With Mason 2.0, Neovim 0.11's `vim.lsp` API, and the new `nvim-treesitter` API, I needed a simple declarative way to manage tools without boilerplate. Many existing plugins were broken or archived after these API changes.

### Is lazy.nvim required?

Not strictly, but `ensure.nvim` is designed for it. Without `lazy.nvim`, you'll need to:
- Ensure dependencies load before `ensure.nvim`
- Handle configuration merging manually
- Use `.nvim.lua` instead of `.lazy.lua` for project configs

## Acknowledgements

Thanks to [@folke](https://github.com/folke) for his amazing work which made:

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

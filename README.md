# 🛠️ AstroLSP

AstroLSP provides a simple API for configuring and setting up language servers in Neovim. This is the LSP configuration engine that [AstroNvim](https://github.com/AstroNvim/AstroNvim) uses, but can be used by itself as well.

## ✨ Features

- Unified interface for configuring language servers:
  - Key mappings when attaching
  - Capabilities and language server settings
- Format on save
- Easily toggle features such as inlay hints, codelens, and semantic tokens

## ⚡️ Requirements

- Neovim >= 0.9

## 📦 Installation

Install the plugin with your plugin manager of choice:

[**lazy.nvim**][lazy]

```lua
{
  "AstroNvim/astrolsp",
  opts = {
    -- set configuration options  as described below
  }
}
```

[**packer.nvim**](https://github.com/wbthomason/packer.nvim)

```lua
use {
  "AstroNvim/astrolsp",
}

require("astrolsp").setup {
  -- set configuration options  as described below
}
```

## ⚙️ Configuration

**AstroLSP** comes with the no defaults, but can be configured fully through the `opts` table in lazy or through calling `require("astrolsp").setup({})`. Here are descriptions of the options and some example usages:

```lua
---@type AstroLSPConfig
local opts = {
  -- Configuration table of features provided by AstroLSP
  features = {
    codelens = true, -- enable/disable codelens refresh on start
    inlay_hints = false, -- enable/disable inlay hints on start
    semantic_tokens = true, -- enable/disable semantic token highlighting
  },
  -- Configure buffer local auto commands to add when attaching a language server
  autocmds = {
    -- first key is the `augroup` (:h augroup)
    lsp_document_highlight = {
      -- condition to create/delete auto command group
      -- can either be a string of a client capability or a function of `fun(client, bufnr): boolean`
      -- condition will be resolved for each client on each execution and if it ever fails for all clients,
      -- the auto commands will be deleted for that buffer
      cond = "textDocument/documentHighlight",
      -- list of auto commands to set
      {
        -- events to trigger
        event = { "CursorHold", "CursorHoldI" },
        -- the rest of the autocmd options (:h nvim_create_autocmd)
        desc = "Document Highlighting",
        callback = function() vim.lsp.buf.document_highlight() end,
      },
      {
        event = { "CursorMoved", "CursorMovedI", "BufLeave" },
        desc = "Document Highlighting Clear",
        callback = function() vim.lsp.buf.clear_references() end,
      },
    },
  },
  -- Configure buffer local user commands to add when attaching a language server
  commands = {
    Format = {
      function() vim.lsp.buf.format() end,
      -- condition to create the user command
      -- can either be a string of a client capability or a function of `fun(client, bufnr): boolean`
      cond = "textDocument/formatting",
      -- the rest of the user command options (:h nvim_create_user_command)
      desc = "Format file with LSP",
    },
  },
  -- Configure default capabilities for language servers (`:h vim.lsp.protocol.make_client.capabilities()`)
  capabilities = {
    textDocument = {
      foldingRange = { dynamicRegistration = false },
    },
  },
  -- Configure language servers for `lspconfig` (`:h lspconfig-setup`)
  config = {
    lua_ls = {
      settings = {
        Lua = {
          hint = { enable = true, arrayIndex = "Disable" },
        },
      },
    },
    clangd = {
      capabilities = {
        offsetEncoding = "utf-8",
      },
    },
  },
  -- A custom flags table to be passed to all language servers  (`:h lspconfig-setup`)
  flags = {
    exit_timeout = 5000,
  },
  -- Configuration options for controlling formatting with language servers
  formatting = {
    -- control auto formatting on save
    format_on_save = {
      -- enable or disable format on save globally
      enabled = true,
      -- enable format on save for specified filetypes only
      allow_filetypes = {
        "go",
      },
      -- disable format on save for specified filetypes
      ignore_filetypes = {
        "python",
      },
    },
    -- disable formatting capabilities for specific language servers
    disabled = {
      "lua_ls",
    },
    -- default format timeout
    timeout_ms = 1000,
    -- fully override the default formatting function
    filter = function(client) return true end,
  },
  -- Configure how language servers get set up
  handlers = {
    -- default handler, first entry with no key
    function(server, opts) require("lspconfig")[server].setup(opts) end,
    -- custom function handler for pyright
    pyright = function(_, opts) require("lspconfig").pyright.setup(opts) end,
    -- set to false to disable the setup of a language server
    rust_analyzer = false,
  },
  -- Configure `vim.lsp.handlers`
  lsp_handlers = {
    ["textDocument/hover"] = vim.lsp.with(vim.lsp.handlers.hover, { border = "rounded", silent = true }),
    ["textDocument/signatureHelp"] = false, -- set to false to disable any custom handlers
  },
  -- Configuration of mappings added when attaching a language server during the core `on_attach` function
  -- The first key into the table is the vim map mode (`:h map-modes`), and the value is a table of entries to be passed to `vim.keymap.set` (`:h vim.keymap.set`):
  --   - The key is the first parameter or the vim mode (only a single mode supported) and the value is a table of keymaps within that mode:
  --     - The first element with no key in the table is the action (the 2nd parameter) and the rest of the keys/value pairs are options for the third parameter.
  --       There is also a special `cond` key which can either be a string of a language server capability or a function with `client` and `bufnr` parameters that returns a boolean of whether or not the mapping is added.
  mappings = {
    -- map mode (:h map-modes)
    n = {
      -- a binding with no condition and therefore is always added
      gl = {
        function() vim.diagnostic.open_float() end,
        desc = "Hover diagnostics",
      },
      -- condition for only server with declaration capabilities
      gD = {
        function() vim.lsp.buf.declaration() end,
        desc = "Declaration of current symbol",
        cond = "textDocument/declaration",
      },
      -- condition with a full function with `client` and `bufnr`
      ["<leader>uY"] = {
        function() require("astrolsp.toggles").buffer_semantic_tokens() end,
        desc = "Toggle LSP semantic highlight (buffer)",
        cond = function(client, bufnr)
          return client.server_capabilities.semanticTokensProvider and vim.lsp.semantic_tokens
        end,
      },
    },
  },
  -- A list like table of servers that should be setup, useful for enabling language servers not installed with Mason.
  servers = { "dartls" },
  -- A custom `on_attach` function to be run after the default `on_attach` function, takes two parameters `client` and `bufnr`  (`:h lspconfig-setup`)
  on_attach = function(client, bufnr) client.server_capabilities.semanticTokensProvider = nil end,
}
```

## 🔌 Integrations

**AstroLSP** can be used as the basis for configuring plugins such as [`nvim-lspconfig`][lspconfig] and [`mason-lspconfig`][mason-lspconfig]. Here are a few examples (using [`lazy.nvim`][lazy] plugin manager):

### [nvim-lspconfig][lspconfig]

```lua
{
  "neovim/nvim-lspconfig",
  dependencies = {
    { "AstroNvim/astrolsp", opts = {} },
  },
  config = function()
    -- set up servers configured with AstroLSP
    vim.tbl_map(require("astrolsp").lsp_setup, require("astrolsp").config.servers)
  end,
}
```

### [nvim-lspconfig][lspconfig] + [mason.nvim][mason] + [mason-lspconfig.nvim][mason-lspconfig]

```lua
{
  "neovim/nvim-lspconfig",
  dependencies = {
    { "AstroNvim/astrolsp", opts = {} },
    {
      "williamboman/mason-lspconfig.nvim", -- MUST be set up before `nvim-lspconfig`
      dependencies = { "williamboman/mason.nvim" },
      opts = function()
        return {
          -- use AstroLSP setup for mason-lspconfig
          handlers = { function(server) require("astrolsp").lsp_setup(server) end },
        }
      end,
    },
  },
  config = function()
    -- set up servers configured with AstroLSP
    vim.tbl_map(require("astrolsp").lsp_setup, require("astrolsp").config.servers)
  end,
}
```

### [none-ls.nvim][none-ls]

```lua
{
  "nvimtools/none-ls.nvim",
  dependencies = {
    { "AstroNvim/astrolsp", opts = {} },
  },
  opts = function() return { on_attach = require("astrolsp").on_attach } end,
}
```

## 📦 API

**AstroLSP** provides a Lua API with utility functions. This can be viewed with `:h astrolsp` or in the repository at [doc/api.md](doc/api.md)

## 🚀 Contributing

If you plan to contribute, please check the [contribution guidelines](https://github.com/AstroNvim/.github/blob/main/CONTRIBUTING.md) first.

[lazy]: https://github.com/folke/lazy.nvim
[lspconfig]: https://github.com/neovim/nvim-lspconfig
[mason]: https://github.com/williamboman/mason.nvim
[mason-lspconfig]: https://github.com/williamboman/mason-lspconfig.nvim
[none-ls]: https://github.com/nvimtools/none-ls.nvim

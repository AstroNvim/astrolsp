# 🛠️ AstroLSP

AstroLSP provides a simple API for configuring and setting up language servers in Neovim. This is the LSP configuration engine that [AstroNvim](https://github.com/AstroNvim/AstroNvim) uses, but can be used by itself as well.

## ✨ Features

- Unified interface for configuring language servers:
  - Key mappings when attaching
  - Capabilities and language server settings
- Format on save
- Easily toggle features such as inlay hints, codelens, and semantic tokens

## ⚡️ Requirements

- Neovim >= 0.11

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
  -- Configure default capabilities for all language servers (`:h vim.lsp.protocol.make_client.capabilities()`)
  capabilities = {
    textDocument = {
      foldingRange = { dynamicRegistration = false },
    },
  },
  defaults = {
    hover = { border = "rounded", silent = true }, -- customize lsp hover window
    signature_help = false, -- disable any default customizations
  },
  -- Configuration of LSP file operation functionality
  file_operations = {
    -- the timeout when executing LSP client operations
    timeout = 10000,
    -- fully disable/enable file operation methods
    operations = {
      willRename = true,
      didRename = true,
      willCreate = true,
      didCreate = true,
      willDelete = true,
      didDelete = true,
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
    -- default handler uses key "*"
    ["*"] = vim.lsp.enable,
    -- custom function handler for pyright
    pyright = function() vim.lsp.enable "pyright" end,
    -- set to false to disable the setup of a language server
    rust_analyzer = false,
  },
  -- Configure `vim.lsp.handlers`
  lsp_handlers = {
    ["textDocument/publishDiagnostics"] = function(...) end, -- customize a handler with a custom function
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
  on_attach = function(client, bufnr)
    -- custom on_attach code to run on all servers
  end,
}
```

## 🔌 Integrations

**AstroLSP** can be used as the basis for configuring plugins such as [`nvim-lspconfig`][lspconfig] and [`mason-lspconfig`][mason-lspconfig]. Here are a few examples (using [`lazy.nvim`][lazy] plugin manager):

### [nvim-lspconfig][lspconfig]

```lua
{
  "AstroNvim/astrolsp",
  dependencies = { "neovim/nvim-lspconfig" },
  opts = {}
}
```

### [nvim-lspconfig][lspconfig] + [mason.nvim][mason] + [mason-lspconfig.nvim][mason-lspconfig]

```lua
{
  "AstroNvim/astrolsp",
  dependencies = {
    "neovim/nvim-lspconfig",
    {
      "williamboman/mason-lspconfig.nvim",
      dependencies = { "williamboman/mason.nvim" },
      opts = {}
    }
  },
  opts = {}
}
```

### [none-ls.nvim][none-ls]

```lua
{
  "nvimtools/none-ls.nvim",
  dependencies = {
    { "AstroNvim/astrolsp", opts = {} },
  },
  opts = {
    on_attach = function(client, bufnr) require("astrolsp").on_attach(client, bufnr) end
  },
}
```

### LSP File Operations

AstroLSP provides an API for triggering LSP based file operations and currently supports:

- `workspace/willCreateFiles`
- `workspace/didCreateFiles`
- `workspace/willDeleteFiles`
- `workspace/didDeleteFiles`
- `workspace/willRenameFiles`
- `workspace/didRenameFiles`

These methods can be integrated with file management plugins such as [mini.files](https://github.com/echasnovski/mini.files), [neo-tree.nvim](https://github.com/nvim-neo-tree/neo-tree.nvim), [nvim-tree.lua](https://github.com/nvim-tree/nvim-tree.lua), and [triptych.nvim](https://github.com/simonmclean/triptych.nvim). (Some file managers already have support out of the box such as [oil.nvim](https://github.com/stevearc/oil.nvim) so integration with them is unnecessary).

#### [mini.files](https://github.com/echasnovski/mini.files)

`mini.files` provides `autocommand` events which can be used to trigger functionality. As of writing these only include events after an operation is completed and therefore does not support the `willCreateFiles`/`willDeleteFiles`/`willRenameFiles` events.

```lua
vim.api.nvim_create_autocmd("User", {
  pattern = "MiniFilesActionCreate",
  desc = "trigger `workspace/didCreateFiles` after creating files",
  callback = function(args) require("astrolsp.file_operations").didCreateFiles(args.data.to) end,
})
vim.api.nvim_create_autocmd("User", {
  pattern = "MiniFilesActionDelete",
  desc = "trigger `workspace/didDeleteFiles` after deleting files",
  callback = function(args) require("astrolsp.file_operations").didDeleteFiles(args.data.from) end,
})
vim.api.nvim_create_autocmd("User", {
  pattern = { "MiniFilesActionRename", "MiniFilesActionMove" },
  desc = "trigger `workspace/didRenameFiles` after renaming or moving files",
  callback = function(args) require("astrolsp.file_operations").didRenameFiles(args.data) end,
})
```

#### [neo-tree.nvim](https://github.com/nvim-neo-tree/neo-tree.nvim)

`neo-tree.nvim` provides configuration options for event handlers which can be used to set up the necessary handling before/after file operations. There is also a Lua API to do this outside of the plugin configuration (information on this can be found in their documentation). Here is an example for doing it within the setup of `neo-tree.nvim`:

```lua
local events = require "neo-tree.events"
require("neo-tree").setup {
  event_handlers = {
    {
      event = events.BEFORE_FILE_ADD,
      handler = function(args) require("astrolsp.file_operations").willCreateFiles(args) end,
    },
    {
      event = events.FILE_ADDED,
      handler = function(args) require("astrolsp.file_operations").didCreateFiles(args) end,
    },
    {
      event = events.BEFORE_FILE_DELETE,
      handler = function(args) require("astrolsp.file_operations").willDeleteFiles(args) end,
    },
    {
      event = events.FILE_DELETED,
      handler = function(args) require("astrolsp.file_operations").didDeleteFiles(args) end,
    },
    {
      event = events.BEFORE_FILE_MOVE,
      handler = function(args)
        require("astrolsp.file_operations").willRenameFiles { from = args.source, to = args.destination }
      end,
    },
    {
      event = events.BEFORE_FILE_RENAME,
      handler = function(args)
        require("astrolsp.file_operations").willRenameFiles { from = args.source, to = args.destination }
      end,
    },
    {
      event = events.FILE_MOVED,
      handler = function(args)
        require("astrolsp.file_operations").didRenameFiles { from = args.source, to = args.destination }
      end,
    },
    {
      event = events.FILE_RENAMED,
      handler = function(args)
        require("astrolsp.file_operations").didRenameFiles { from = args.source, to = args.destination }
      end,
    },
  },
}
```

#### [nvim-tree.lua](https://github.com/nvim-tree/nvim-tree.lua)

`nvim-tree.lua` provides a Lua API to subscribe to file operation events which can be easily accessed through an `autocommand` which runs after the plugin is setup.

```lua
vim.api.nvim_create_autocmd("User", {
  pattern = "NvimTreeSetup",
  desc = "Subscribe file operation events to AstroLSP file operations",
  callback = function()
    local events = require("nvim-tree.api").events
    events.subscribe(
      events.Event.WillCreateFile,
      function(args) require("astrolsp.file_operations").willCreateFiles(args.fname) end
    )
    events.subscribe(
      events.Event.FileCreated,
      function(args) require("astrolsp.file_operations").didCreateFiles(args.fname) end
    )
    events.subscribe(
      events.Event.WillRemoveFile,
      function(args) require("astrolsp.file_operations").willDeleteFiles(args.fname) end
    )
    events.subscribe(
      events.Event.FileRemoved,
      function(args) require("astrolsp.file_operations").didDeleteFiles(args.fname) end
    )
    events.subscribe(
      events.Event.WillRenameNode,
      function(args) require("astrolsp.file_operations").willRenameFiles { from = args.old_name, to = args.new_name } end
    )
    events.subscribe(
      events.Event.NodeRenamed,
      function(args) require("astrolsp.file_operations").didRenameFiles { from = args.old_name, to = args.new_name } end
    )
  end,
})
```

#### [triptych.nvim](https://github.com/simonmclean/triptych.nvim)

`triptych.nvim` provides `autocommand` events which can be used to trigger functionality.

```lua
vim.api.nvim_create_autocmd("User", {
  pattern = "TriptychWillCreateNode",
  desc = "trigger `workspace/willCreateFiles` before creating files",
  callback = function(args) require("astrolsp.file_operations").willCreateFiles(args.data.path) end,
})
vim.api.nvim_create_autocmd("User", {
  pattern = "TriptychDidCreateNode",
  desc = "trigger `workspace/didCreateFiles` after creating files",
  callback = function(args) require("astrolsp.file_operations").didCreateFiles(args.data.path) end,
})
vim.api.nvim_create_autocmd("User", {
  pattern = "TriptychWillDeleteNode",
  desc = "trigger `workspace/willDeleteFiles` before deleting files",
  callback = function(args) require("astrolsp.file_operations").willDeleteFiles(args.data.path) end,
})
vim.api.nvim_create_autocmd("User", {
  pattern = "TriptychDidDeleteNode",
  desc = "trigger `workspace/didDeleteFiles` after deleting files",
  callback = function(args) require("astrolsp.file_operations").didDeleteFiles(args.data.path) end,
})
vim.api.nvim_create_autocmd("User", {
  pattern = "TriptychWillMoveNode",
  desc = "trigger `workspace/willRenameFiles` before moving files",
  callback = function(args)
    require("astrolsp.file_operations").willRenameFiles { from = args.data.from_path, to = args.data.to_path }
  end,
})
vim.api.nvim_create_autocmd("User", {
  pattern = "TriptychDidMoveNode",
  desc = "trigger `workspace/didRenameFiles` after moving files",
  callback = function(args)
    require("astrolsp.file_operations").didRenameFiles { from = args.data.from_path, to = args.data.to_path }
  end,
})
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

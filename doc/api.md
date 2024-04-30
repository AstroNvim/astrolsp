# Lua API

astrolsp API documentation

## astrolsp

AstroNvim LSP Utilities

Various utility functions to use within AstroNvim for the LSP engine

This module can be loaded with `local astro = require "astrolsp"`

copyright 2023
license GNU General Public License v3.0

### attached_clients


```lua
table
```

 A table of LSP clients that have been attached with AstroLSP

### config


```lua
AstroLSPOpts
```

 The configuration as set by the user through the `setup()` function

### format_opts


```lua
unknown
```

 Format options that are passed into the `vim.lsp.buf.format` (`:h vim.lsp.buf.format()`)

### lsp_opts


```lua
function astrolsp.lsp_opts(server_name: string)
  -> table
```

 Get the server configuration for a given language server to be provided to the server's `setup()` call

*param* `server_name` — The name of the server

*return* — The table of LSP options used when setting up the given language server

### lsp_progress


```lua
table
```

 A table of lsp progress messages that can be used to display LSP progress in a statusline

### lsp_setup


```lua
function astrolsp.lsp_setup(server: string)
```

 Helper function to set up a given server with the Neovim LSP client

*param* `server` — The name of the server to be setup

### on_attach


```lua
function astrolsp.on_attach(client: vim.lsp.Client, bufnr: integer)
```

*param* `client` — The LSP client details when attaching

*param* `bufnr` — The buffer that the LSP client is attaching to

 The `on_attach` function used by AstroNvim

### progress


```lua
function astrolsp.progress(data: { client_id: integer, result: lsp.ProgressParams })
```

 Add a new LSP progress message to the message queue

### setup


```lua
function astrolsp.setup(opts: AstroLSPOpts)
```

 Setup and configure AstroLSP

*param* `opts` — options passed by the user to configure AstroLSP


## astrolsp.toggles

AstroNvim LSP Toggles

Utility functions for easy LSP toggles

This module can be loaded with `local ui = require("astrolsp.toggles")`

copyright 2023
license GNU General Public License v3.0

### autoformat


```lua
function astrolsp.toggles.autoformat(silent?: boolean)
```

 Toggle auto format

*param* `silent` — if true then don't sent a notification

### buffer_autoformat


```lua
function astrolsp.toggles.buffer_autoformat(bufnr?: integer, silent?: boolean)
```

 Toggle buffer local auto format

*param* `bufnr` — The buffer to toggle the autoformatting of, default the current buffer

*param* `silent` — if true then don't sent a notification

### buffer_inlay_hints


```lua
function astrolsp.toggles.buffer_inlay_hints(bufnr?: integer, silent?: boolean)
```

 Toggle buffer LSP inlay hints

*param* `bufnr` — the buffer to toggle the clients on

*param* `silent` — if true then don't sent a notification

### buffer_semantic_tokens


```lua
function astrolsp.toggles.buffer_semantic_tokens(bufnr?: integer, silent?: boolean)
```

 Toggle buffer semantic token highlighting for all language servers that support it

*param* `bufnr` — the buffer to toggle the clients on

*param* `silent` — if true then don't sent a notification

### codelens


```lua
function astrolsp.toggles.codelens(silent?: boolean)
```

 Toggle codelens

*param* `silent` — if true then don't sent a notification



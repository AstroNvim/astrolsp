# Lua API

astrolsp API documentation

## astrolsp

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

 The `on_attach` function used by AstroNvim

*param* `client` — The LSP client details when attaching

*param* `bufnr` — The buffer that the LSP client is attaching to

### progress


```lua
function astrolsp.progress(data: { client_id: integer, params: lsp.ProgressParams })
```

 Add a new LSP progress message to the message queue

### setup


```lua
function astrolsp.setup(opts: AstroLSPOpts)
```

 Setup and configure AstroLSP

*param* `opts` — options passed by the user to configure AstroLSP


## astrolsp.file_operations

### didCreateFiles


```lua
function astrolsp.file_operations.didCreateFiles(fnames: string|string[])
```

 Notify LSP clients that file(s) were created

*param* `fnames` — a file or list of files that were created

### didDeleteFiles


```lua
function astrolsp.file_operations.didDeleteFiles(fnames: string|string[])
```

 Notify LSP clients that file(s) were deleted

*param* `fnames` — a file or list of files that were deleted

### didRenameFiles


```lua
function astrolsp.file_operations.didRenameFiles(renames: AstroLSPFileOperationsRename|AstroLSPFileOperationsRename[])
```

 Notify LSP clients that file(s) were renamed

*param* `renames` — a table or list of tables of files that were renamed

### willCreateFiles


```lua
function astrolsp.file_operations.willCreateFiles(fnames: string|string[])
```

 Notify LSP clients that file(s) are going to be created

*param* `fnames` — a file or list of files that will be created

### willDeleteFiles


```lua
function astrolsp.file_operations.willDeleteFiles(fnames: string|string[])
```

 Notify LSP clients that file(s) are going to be deleted

*param* `fnames` — a file or list of files that will be deleted

### willRenameFiles


```lua
function astrolsp.file_operations.willRenameFiles(renames: AstroLSPFileOperationsRename|AstroLSPFileOperationsRename[])
```

 Notify LSP clients that file(s) are going to be renamed

*param* `renames` — a table or list of tables of files that will be renamed


## astrolsp.mason-lspconfig

### register_server


```lua
function astrolsp.mason-lspconfig.register_server(server: string, spec: AstroLSPMasonLspconfigServer)
```

 Register a new language server with mason-lspconfig

*param* `server` — the server name in lspconfig

*param* `spec` — the details for registering the server

### register_servers


```lua
function astrolsp.mason-lspconfig.register_servers(server_specs?: { [string]: AstroLSPMasonLspconfigServer })
```

 Register multiple new language servers with mason-lspconfig


## astrolsp.toggles

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

### buffer_signature_help


```lua
function astrolsp.toggles.buffer_signature_help(bufnr?: integer, silent?: boolean)
```

 Toggle buffer local automatic signature help

*param* `bufnr` — The buffer to toggle the auto signature help of, default the current buffer

*param* `silent` — if true then don't sent a notification

### codelens


```lua
function astrolsp.toggles.codelens(silent?: boolean)
```

 Toggle codelens

*param* `silent` — if true then don't sent a notification

### inlay_hints


```lua
function astrolsp.toggles.inlay_hints(silent?: boolean)
```

 Toggle global LSP inlay hints

*param* `silent` — if true then don't sent a notification

### signature_help


```lua
function astrolsp.toggles.signature_help(silent?: boolean)
```

 Toggle automatic signature help

*param* `silent` — if true then don't sent a notification


## astrolsp.utils

### notify


```lua
function astrolsp.utils.notify(client: vim.lsp.Client, method: string, params?: table)
```

 Helper function to support deprecated notify usage

### request_sync


```lua
function astrolsp.utils.request_sync(client: vim.lsp.Client, req: string, params: table, timeout?: integer, bufnr?: integer)
```

 Helper function to support deprecated request_sync usage

### supports_method


```lua
function astrolsp.utils.supports_method(client: vim.lsp.Client, method: string, bufnr?: integer)
```

 Helper function to support deprecated supports_method usage



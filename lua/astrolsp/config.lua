-- AstroNvim LSP Configuration
--
-- This module simply defines the configuration table structure for `opts` used in:
--
--    require("astrolsp").setup(opts)
--
-- copyright 2023
-- license GNU General Public License v3.0

---@alias AstroLSPCondition string|boolean|fun(client:vim.lsp.Client,bufnr:integer):boolean conditional for doing something when attaching a language server

---@class AstroLSPMapping: vim.api.keyset.keymap
---@field [1] string|function rhs of keymap
---@field name string? optional which-key mapping name
---@field cond AstroLSPCondition? condition for whether or not to set the mapping during language server attachment

---@class AstroLSPCommand: vim.api.keyset.user_command
---@field [1] string|function the command to execute
---@field cond AstroLSPCondition? condition for whether or not to create the user command during language server attachment

---@class AstroLSPAutocmd: vim.api.keyset.create_autocmd
---@field event string|string[] Event(s) that will trigger the handler

---@class AstroLSPAutocmds
---@field cond AstroLSPCondition? condition for whether or not to create the auto commands during language server attachment
---@field [integer] AstroLSPAutocmd an autocommand definition

---@class AstroLSPFeatureOpts
---@field codelens boolean? enable/disable codelens refresh on start (boolean; default = true)
---@field inlay_hints boolean? enable/disable inlay hints on start (boolean; default = false)
---@field semantic_tokens boolean? enable/disable semantic token highlighting (boolean; default = true)

---@class AstroLSPFormatOnSaveOpts
---@field enabled boolean? enable or disable format on save globally
---@field allow_filetypes string[]? a list like table of filetypes to whitelist formatting on save
---@field ignore_filetypes string[]? a list like table of filetypes to blacklist formatting on save
---@field filter (fun(bufnr):boolean)? a function for doing a custom format on save filter based on buffer number

---@class AstroLSPFormatOpts
---@field format_on_save boolean|AstroLSPFormatOnSaveOpts? control formatting on save options
---@field disabled true|string[]? true to disable all or a list like table of language server names to disable formatting
---@field timeout_ms integer? configure the timeout length for formatting
---@field filter (fun(client):boolean)? fully override the default formatting filter function

---@class AstroLSPOpts
---Configuration of auto commands
---The key into the table is the group name for the auto commands (`:h augroup`) and the value
---is a list of autocmd tables where `event` key is the event(s) that trigger the auto command
---and the rest are auto command options (`:h nvim_create_autocmd`). A `cond` key can also be
---added to the list to control when an `augroup` should be added as well as deleted if it's never matching
---Example:
---
---```lua
---autocmds = {
---  -- first key is the `augroup` (:h augroup)
---  lsp_document_highlight = {
---    -- condition to create/delete auto command group
---    cond = "textDocument/documentHighlight",
---    -- list of auto commands to set
---    {
---      -- events to trigger
---      event = { "CursorHold", "CursorHoldI" },
---      -- the rest of the autocmd options (:h nvim_create_autocmd)
---      desc = "Document Highlighting",
---      callback = function() vim.lsp.buf.document_highlight() end
---    },
---    {
---      event = { "CursorMoved", "CursorMovedI", "BufLeave" },
---      desc = "Document Highlighting Clear",
---      callback = function() vim.lsp.buf.clear_references() end
---    }
---  }
---}
---```
---@field autocmds table<string,AstroLSPAutocmds|false>?
---Configuration of user commands
---The key into the table is the name of the user command and the value is a table of command options. A `cond` key
---be added to control whether or not the user command is created when the language server is created.
---Example:
---
---```lua
---commands = {
---  -- key is the command name
---  Format = {
---    -- first element with no key is the command (string or function)
---    function() vim.lsp.buf.format() end,
---    -- condition to create the user command
---    cond = "textDocument/formatting",
---    -- the rest are options for creating user commands (:h nvim_create_user_command)
---    desc = "Format file with LSP",
---  }
---}
---```
---@field commands table<string,AstroLSPCommand|false>?
---Configuration table of features provided by AstroLSP
---Example:
--
---```lua
---features = {
---  codelens = true,
---  inlay_hints = false,
---  semantic_tokens = true,
---}
---```
---@field features AstroLSPFeatureOpts?
---Configure default capabilities for language servers (`:h vim.lsp.protocol.make_client.capabilities()`)
---Example
--
---```lua
---capabilities = {
---  textDocument = {
---    foldingRange = { dynamicRegistration = false }
---  }
---}
---```
---@field capabilities lsp.ClientCapabilities?
---Configure language servers for `lspconfig` (`:h lspconfig-setup`)
---Example:
--
---```lua
---config = {
---  lua_ls = {
---    settings = {
---      Lua = {
---        hint = { enable = true, arrayIndex = "Disable" }
---      }
---    }
---  },
---  clangd = { capabilities = { offsetEncoding = "utf-8" } },
---}
---```
---@field config lspconfig.options?
---A custom flags table to be passed to all language servers  (`:h lspconfig-setup`)
---Example:
--
---```lua
---flags = { exit_timeout = 5000 }
---```
---@field flags table?
---Configuration options for controlling formatting with language servers
---Example:
--
---```lua
---formatting = {
---  -- control auto formatting on save
---  format_on_save = {
---    -- enable or disable format on save globally
---    enabled = true,
---    -- enable format on save for specified filetypes only
---    allow_filetypes = {
---      "go",
---    },
---    -- disable format on save for specified filetypes
---    ignore_filetypes = {
---      "python",
---    },
---  },
---  -- disable formatting capabilities for specific language servers
---  disabled = {
---    "lua_ls",
---  },
---  -- default format timeout
---  timeout_ms = 1000,
---  -- fully override the default formatting function
---  filter = function(client)
---    return true
---  end
---}
---```
---@field formatting AstroLSPFormatOpts?
---Configure how language servers get set up
---Example:
--
---```lua
---handlers = {
---  -- default handler
---  function(server, opts)
---    require("lspconfig")[server].setup(opts)
---  end,
---  -- custom function handler for pyright
---  pyright = function(_, opts)
---    require("lspconfig").pyright.setup(opts)
---  end,
---  -- set to false to disable the setup of a language server
---  rust_analyzer = false,
---}
---```
---@field handlers table<string|integer,fun(server:string,opts:_.lspconfig.options)|boolean?>?
---Configure global LSP handlers, set a method to `false` to use the Neovim default
---Example:
--
---```lua
---handlers = {
---  -- custom function handler for pyright
---  ["textDocument/hover"] = vim.lsp.with(
---    vim.lsphandlers.hover, {
---      border = "single",
---      title = "hover",
---    }
---  )
---}
---```
---@field lsp_handlers table<string,lsp.Handler|false>|false?
---Configuration of mappings added when attaching a language server during the core `on_attach` function
---The first key into the table is the vim map mode (`:h map-modes`), and the value is a table of entries to be passed to `vim.keymap.set` (`:h vim.keymap.set`):
---  - The key is the first parameter or the vim mode (only a single mode supported) and the value is a table of keymaps within that mode:
---    - The first element with no key in the table is the action (the 2nd parameter) and the rest of the keys/value pairs are options for the third parameter. There is also a special `cond` key which can either be a string of a language server capability or a function with `client` and `bufnr` parameters that returns a boolean of whether or not the mapping is added.
---Example:
--
---```lua
---mappings = {
---  -- map mode (:h map-modes)
---  n = {
---    -- a binding with no condition and therefore is always added
---    gl = {
---      function() vim.diagnostic.open_float() end,
---      desc = "Hover diagnostics"
---    },
---    -- condition for only server with declaration capabilities
---    gD = {
---      function() vim.lsp.buf.declaration() end,
---      desc = "Declaration of current symbol",
---      cond = "textDocument/declaration",
---    },
---    -- condition with a full function with `client` and `bufnr`
---    ["<leader>uY"] = {
---      function()
---        require("astrolsp.toggles").buffer_semantic_tokens()
---      end,
---      desc = "Toggle LSP semantic highlight (buffer)",
---      cond = function(client, bufnr)
---        return client.server_capabilities.semanticTokensProvider
---           and vim.lsp.semantic_tokens
---      end,
---    },
---  }
---}
---```
---@field mappings table<string,table<string,(AstroLSPMapping|string|false)?>?>?
---A list like table of servers that should be setup, useful for enabling language servers not installed with Mason.
---Example:
--
---```lua
---servers = { "dartls" }
---```
---@field servers string[]?
---A custom `on_attach` function to be run after the default `on_attach` function, takes two parameters `client` and `bufnr`  (`:h lspconfig-setup`)
---Example:
--
---```lua
---on_attach = function(client, bufnr)
---  client.server_capabilities.semanticTokensProvider = nil
---end
---```
---@field on_attach fun(client:vim.lsp.Client,bufnr:integer)?

---@type AstroLSPOpts
local M = {
  autocmds = {},
  commands = {},
  features = {
    codelens = true,
    inlay_hints = false,
    semantic_tokens = true,
  },
  capabilities = {},
  ---@diagnostic disable-next-line: missing-fields
  config = {},
  flags = {},
  formatting = { format_on_save = { enabled = true }, disabled = {} },
  handlers = {},
  lsp_handlers = {},
  mappings = {},
  servers = {},
  on_attach = nil,
}

return M

-- AstroNvim LSP Configuration
--
-- This module simply defines the configuration table structure for `opts` used in:
--
--    require("astrolsp").setup(opts)
--
-- copyright 2023
-- license GNU General Public License v3.0

---@class AstroLSPFeatureOpts
---@field autoformat boolean? enable or disable auto formatting on start (boolean' default = true)
---@field codelens boolean? enable/disable codelens refresh on start (boolean; default = true)
---@field diagnostics_mode integer? diagnostic mode on start (0 = off, 1 = no signs/virtual text, 2 = no virtual text, 3 = off; default = 3)
---@field inlay_hints boolean? enable/disable inlay hints on start (boolean; default = false)
---@field lsp_handlers boolean? enable/disable setting of lsp_handlers (boolean; default = true)
---@field semantic_tokens boolean? enable/disable semantic token highlighting (boolean; default = true)

---@class AstroLSPFormatOnSaveOpts
---@field enabled boolean? enable or disable format on save globally
---@field allow_filetypes string[]? a list like table of filetypes to whitelist formatting on save
---@field ignore_filetypes string[]? a list like table of filetypes to blacklist formatting on save

---@class AstroLSPFormatOpts
---@field format_on_save boolean|AstroLSPFormatOnSaveOpts? control formatting on save options
---@field disabled string[]? a list like table of language server names to disable formatting
---@field timeout_ms integer? configure the timeout length for formatting
---@field filter (fun(client):boolean)? fully override the default formatting filter function

---@class AstroLSPOpts
---Configuration table of features provided by AstroLSP
---Example:
--
---```lua
---features = {
---  autoformat = true,
---  codelens = true,
---  diagnostics_mode = 3,
---  inlay_hints = false,
---  lsp_handlers = true,
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
---Configure diagnostics options (`:h vim.diagnostic.config()`)
---Example:
--
---```lua
---diagnostics = { update_in_insert = false },
---```
---@field diagnostics table?
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
---@field formatting AstroLSPFormatOpts
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
---@field mappings table<string,table<string,(table|boolean|string)?>?>?
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
---@field on_attach fun(client:lsp.Client,bufnr:integer)?

---@type AstroLSPOpts
local M = {
  features = {
    autoformat = true,
    codelens = true,
    diagnostics_mode = 3,
    inlay_hints = false,
    lsp_handlers = true,
    semantic_tokens = true,
  },
  capabilities = {},
  config = {},
  diagnostics = {},
  flags = {},
  formatting = { format_on_save = { enabled = true }, disabled = {} },
  handlers = {},
  mappings = {},
  servers = {},
  on_attach = nil,
}

return M

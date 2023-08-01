--- ### AstroNvim LSP Configuration
--
-- This module simply defines the configuration table structure for `opts` used in the `require("astrolsp").setup(opts)` call
--
-- @module astrolsp.config
-- @copyright 2023
-- @license GNU General Public License v3.0

return {
  --- Configuration table of features provided by AstroLSP
  -- @usage features = {
  --   autoformat_enabled = true,
  --   codelens = true,
  --   diagnostics_mode = 3,
  --   inlay_hints = false,
  --   lsp_handlers = true,
  --   semantic_tokens = true,
  -- }
  features = {
    autoformat_enabled = true, -- enable or disable auto formatting on start (boolean' default = true)
    codelens = true, -- enable/disable codelens refresh on start (boolean; default = true)
    diagnostics_mode = 3, -- diagnostic mode on start (0 = off, 1 = no signs/virutal text, 2 = no virtual text, 3 = off; default = 3)
    inlay_hints = false, -- enable/disable inlay hints on start (boolean; default = false)
    lsp_handlers = true, -- enable/disable setting of lsp_handlers (boolean; default = true)
    semantic_tokens = true, -- enable/disable semantic token highlighting (boolean; default = true)
  },
  --- Configure default capabilities for language servers (`:h vim.lsp.protocol.make_client.capabilities()`)
  capabilities = {},
  --- Configure language servers for `lspconfig` (`:h lspconfig-setup`)
  -- @field server_name the custom `opts` table that would be passed into `require("lspconfig")[server_name].setup(opts)`
  -- @usage config = {
  --   lua_ls = { settings = { Lua = { hint = { enable = true, arrayIndex = "Disable" } } } },
  --   clangd = { capabilities = { offsetEncoding = "utf-8" } },
  -- }
  config = {},
  --- Confiure diagnostics options (`:h vim.diagnostic.config()`)
  -- @usage diagnostics = { update_in_insert = false },
  diagnostics = {},
  --- A custom flags table to be passed to all language servers  (`:h lspconfig-setup`)
  flags = {},
  --- Configuration options for controlling formatting with language servers
  -- @field format_on_save controlling formatting on save options
  -- @field disabled a list like table of language server names to disable formatting
  -- @field timeout_ms configure the timeout length for formatting
  formatting = { format_on_save = { enabled = true }, disabled = {} },
  --- Configure how language servers get set up
  -- @field 1 the default handler function for setting up language servers
  -- @field server_name the custom handler function for setting up language server, `server_name`
  -- @usage handlers = {
  --   function(server, opts) require("lspconfig")[server].setup(opts) end
  --   rust_analyzer = false,
  --   pyright = function(_, opts) require("lspconfig").pyright.setup(opts) end,
  -- }
  handlers = {},
  --- Configuration of mappings added when attaching a language server
  mappings = {},
  --- A list like table of servers that should be setup, useful for enabling language servers not installed with Mason.
  servers = {},
  --- A custom `on_attach` function to be run after the default `on_attach` function, takes two parameters `client` and `bufnr`  (`:h lspconfig-setup`)
  on_attach = nil,
}

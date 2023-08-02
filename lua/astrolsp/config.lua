--- ### AstroNvim LSP Configuration
--
-- This module simply defines the configuration table structure for `opts` used in:
--
--    require("astrolsp").setup(opts)
--
-- @module astrolsp.config
-- @copyright 2023
-- @license GNU General Public License v3.0

---@type AstroLSPConfig
return {
  --- Configuration table of features provided by AstroLSP
  -- @usage features = {
  --   autoformat = true,
  --   codelens = true,
  --   diagnostics_mode = 3,
  --   inlay_hints = false,
  --   lsp_handlers = true,
  --   semantic_tokens = true,
  -- }
  features = {
    autoformat = true, -- enable or disable auto formatting on start (boolean' default = true)
    codelens = true, -- enable/disable codelens refresh on start (boolean; default = true)
    diagnostics_mode = 3, -- diagnostic mode on start (0 = off, 1 = no signs/virtual text, 2 = no virtual text, 3 = off; default = 3)
    inlay_hints = false, -- enable/disable inlay hints on start (boolean; default = false)
    lsp_handlers = true, -- enable/disable setting of lsp_handlers (boolean; default = true)
    semantic_tokens = true, -- enable/disable semantic token highlighting (boolean; default = true)
  },
  --- Configure default capabilities for language servers (`:h vim.lsp.protocol.make_client.capabilities()`)
  -- @usage capabilities = {
  --   textDocument = {
  --     foldingRange = { dynamicRegistration = false }
  --   }
  -- }
  capabilities = {},
  --- Configure language servers for `lspconfig` (`:h lspconfig-setup`)
  -- @field server_name the custom `opts` table that would be passed into `require("lspconfig")[server_name].setup(opts)`
  -- @usage config = {
  --   lua_ls = {
  --     settings = {
  --       Lua = {
  --         hint = { enable = true, arrayIndex = "Disable" }
  --       }
  --     }
  --   },
  --   clangd = { capabilities = { offsetEncoding = "utf-8" } },
  -- }
  config = {},
  --- Configure diagnostics options (`:h vim.diagnostic.config()`)
  -- @usage diagnostics = { update_in_insert = false },
  diagnostics = {},
  --- A custom flags table to be passed to all language servers  (`:h lspconfig-setup`)
  -- @usage flags = { exit_timeout = 5000 }
  flags = {},
  --- Configuration options for controlling formatting with language servers
  -- @field format_on_save controlling formatting on save options. A table with the keys:
  --
  --  `enabled`: boolean to enable or disable format on save globally
  --  `allow_filetypes`: a list like table of filetypes to whitelist formatting on save
  --  `ignore_filetypes`: a list like table of filetypes to blacklist formatting on save
  --
  -- @field disabled a list like table of language server names to disable formatting
  -- @field timeout_ms configure the timeout length for formatting
  -- @field filter fully override the default formatting filter function
  -- @usage formatting = {
  --   -- control auto formatting on save
  --   format_on_save = {
  --     -- enable or disable format on save globally
  --     enabled = true,
  --     -- enable format on save for specified filetypes only
  --     allow_filetypes = {
  --       "go",
  --     },
  --     -- disable format on save for specified filetypes
  --     ignore_filetypes = {
  --       "python",
  --     },
  --   },
  --   -- disable formatting capabilities for specific language servers
  --   disabled = {
  --     "lua_ls",
  --   },
  --   -- default format timeout
  --   timeout_ms = 1000,
  --   -- fully override the default formatting function
  --   filter = function(client)
  --     return true
  --   end
  -- }
  formatting = { format_on_save = { enabled = true }, disabled = {} },
  --- Configure how language servers get set up
  -- @field 1 the default handler function for setting up language servers
  -- @field server_name the custom handler function for setting up a language server
  -- @usage handlers = {
  --   -- default handler
  --   function(server, opts)
  --     require("lspconfig")[server].setup(opts)
  --   end
  --   -- custom function handler for pyright
  --   pyright = function(_, opts)
  --     require("lspconfig").pyright.setup(opts)
  --   end,
  --   -- set to false to disable the setup of a language server
  --   rust_analyzer = false,
  -- }
  handlers = {},
  --- Configuration of mappings added when attaching a language server during the core `on_attach` function
  --
  -- @field mode The key, `mode` is the vim map mode (`:h map-modes`), and the value is a table of entries to be passed to `vim.keymap.set` (`:h vim.keymap.set`):
  --
  --   The key is the first parameter or the vim mode (only a single mode supported) and the value is a table of keymaps within that mode:
  --
  --   The first element with no key in the table is the action (the 2nd parameter) and the rest of the keys/value pairs are options for the third parameter. There is also a special `cond` key which can either be a string of a language server capability or a function with `client` and `bufnr` parameters that returns a boolean of whether or not the mapping is added.
  -- @usage mappings = {
  --   -- map mode (:h map-modes)
  --   n = {
  --     -- a binding with no condition and therefore is always added
  --     gl = {
  --       function() vim.diagnostic.open_float() end,
  --       desc = "Hover diagnostics"
  --     },
  --     -- condition for only server with declaration capabilities
  --     gD = {
  --       function() vim.lsp.buf.declaration() end,
  --       desc = "Declaration of current symbol",
  --       cond = "textDocument/declaration",
  --     },
  --     -- condition with a full function with `client` and `bufnr`
  --     ["<leader>uY"] = {
  --       function()
  --         require("astrolsp.toggles").buffer_semantic_tokens()
  --       end,
  --       desc = "Toggle LSP semantic highlight (buffer)",
  --       cond = function(client, bufnr)
  --         return client.server_capabilities.semanticTokensProvider
  --            and vim.lsp.semantic_tokens
  --       end,
  --     },
  --   }
  -- }
  mappings = {},
  --- A list like table of servers that should be setup, useful for enabling language servers not installed with Mason.
  -- @usage servers = { "dartls" }
  servers = {},
  --- A custom `on_attach` function to be run after the default `on_attach` function, takes two parameters `client` and `bufnr`  (`:h lspconfig-setup`)
  -- @usage on_attach = function(client, bufnr)
  --   client.server_capabilities.semanticTokensProvider = nil
  -- end
  on_attach = nil,
}

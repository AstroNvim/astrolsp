return {
  diagnostics = {
    virtual_text = true,
    signs = {
      active = {
        { name = "DiagnosticSignError", text = "", texthl = "DiagnosticSignError" },
        { name = "DiagnosticSignHint", text = "󰌵", texthl = "DiagnosticSignHint" },
        { name = "DiagnosticSignInfo", text = "󰋼", texthl = "DiagnosticSignInfo" },
        { name = "DiagnosticSignWarn", text = "", texthl = "DiagnosticSignWarn" },
        { name = "DapBreakpoint", text = "", texthl = "DiagnosticInfo" },
        { name = "DapBreakpointCondition", text = "", texthl = "DiagnosticInfo" },
        { name = "DapBreakpointRejected", text = "", texthl = "DiagnosticError" },
        { name = "DapLogPoint", text = ".>", texthl = "DiagnosticInfo" },
        { name = "DapStopped", text = "󰁕", texthl = "DiagnosticWarn" },
      },
    },
    update_in_insert = true,
    underline = true,
    severity_sort = true,
    float = {
      focused = false,
      style = "minimal",
      border = "rounded",
      source = "always",
      header = "",
      prefix = "",
    },
  },

  capabilities = vim.tbl_deep_extend("force", vim.lsp.protocol.make_client_capabilities(), {
    textDocument = {
      completion = {
        completionItem = {
          documentationFormat = { "markdown", "plaintext" },
          snippetSupport = true,
          preselectSupport = true,
          insertReplaceSupport = true,
          labelDetailsSupport = true,
          deprecatedSupport = true,
          commitCharactersSupport = true,
          tagSupport = { valueSet = { 1 } },
          resolveSupport = { properties = { "documentation", "detail", "additionalTextEdits" } },
        },
      },
      foldingRange = { dynamicRegistration = false, lineFoldingOnly = true },
    },
  }),

  flags = {},

  config = {},

  -- on_attach = function(client, bufnr) ... end, -- user can pass in an extension of the on_attach

  setup_handlers = {
    function(server, opts) require("lspconfig")[server].setup(opts) end,
  },

  formatting = { format_on_save = { enabled = true }, disable = {} },

  mappings = require "astrolsp.config.mappings",
}

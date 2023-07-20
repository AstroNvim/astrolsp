return {
  features = {
    autoformat_enabled = true,
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
  mappings = {},
  servers = {},
  setup_handlers = { function(server, opts) require("lspconfig")[server].setup(opts) end },
  on_attach = nil,
}

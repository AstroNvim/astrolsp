local M = {}

for _, mode in ipairs { "", "n", "v", "x", "s", "o", "!", "i", "l", "c", "t" } do
  M[mode] = {}
end
if vim.fn.has "nvim-0.10.0" == 1 then
  for _, abbr_mode in ipairs { "ia", "ca", "!a" } do
    M[abbr_mode] = {}
  end
end

M.n["<leader>ld"] = { function() vim.diagnostic.open_float() end, desc = "Hover diagnostics" }
M.n["[d"] = { function() vim.diagnostic.goto_prev() end, desc = "Previous diagnostic" }
M.n["]d"] = { function() vim.diagnostic.goto_next() end, desc = "Next diagnostic" }
M.n["gl"] = { function() vim.diagnostic.open_float() end, desc = "Hover diagnostics" }

M.n["<leader>lD"] = {
  function() require("telescope.builtin").diagnostics() end,
  desc = "Search diagnostics",
  cond = function(_, _) return true end, -- client, bufnr parameters
}

M.n["<leader>la"] = {
  function() vim.lsp.buf.code_action() end,
  desc = "LSP code action",
  cond = "testDocument/codeAction", -- LSP client capability string
}
M.v["<leader>la"] = M.n["<leader>la"]

M.n["<leader>ll"] =
  { function() vim.lsp.codelens.refresh() end, desc = "LSP CodeLens refresh", cond = "textDocument/codeLens" }
M.n["<leader>lL"] = { function() vim.lsp.codelens.run() end, desc = "LSP CodeLens run", cond = "textDocument/codeLens" }

M.n["gD"] = {
  function() vim.lsp.buf.declaration() end,
  desc = "Declaration of current symbol",
  cond = "textDocument/declaration",
}
M.n["gd"] = {
  function() vim.lsp.buf.definition() end,
  desc = "Show the definition of current symbol",
  cond = "textDocument/definition",
}

M.n["<leader>lf"] =
  { function() vim.lsp.buf.format(M.format_opts) end, desc = "Format buffer", cond = "textDocument/formatting" }
M.v["<leader>lf"] = M.n["<leader>lf"]
M.n["<leader>uf"] = {
  function() require("astrolsp.utils").toggle_buffer_autoformat() end,
  desc = "Toggle autoformatting (buffer)",
  cond = "textDocument/formatting",
}
M.n["<leader>uF"] = {
  function() require("astrolsp.utils").toggle_autoformat() end,
  desc = "Toggle autoformatting (global)",
  cond = "textDocument/formatting",
}

M.n["K"] = { function() vim.lsp.buf.hover() end, desc = "Hover symbol details", cond = "textDocument/hover" }

M.n["gI"] = {
  function() vim.lsp.buf.implementation() end,
  desc = "Implementation of current symbol",
  cond = "textDocument/implementation",
}

M.n["<leader>uH"] = {
  function()
    vim.b.inlay_hints_enabled = not vim.b.inlay_hints_enabled
    -- TODO: remove check after dropping support for Neovim v0.9
    if vim.lsp.inlay_hint then
      vim.lsp.inlay_hint(0, vim.b.inlay_hints_enabled)
      vim.notify(("Inlay hints %s"):format(vim.b.inlay_hints_enabled and "on" or "off"))
    end
  end,
  desc = "Toggle LSP inlay hints (buffer)",
  cond = vim.lsp.inlay_hint and "textDocument/inlayHint" or false,
}

M.n["gr"] =
  { function() vim.lsp.buf.references() end, desc = "References of current symbol", cond = "textDocument/references" }
M.n["<leader>lR"] =
  { function() vim.lsp.buf.references() end, desc = "Search references", cond = "textDocument/references" }

M.n["<leader>lr"] =
  { function() vim.lsp.buf.rename() end, desc = "Rename current symbol", cond = "textDocument/rename" }

M.n["<leader>lh"] =
  { function() vim.lsp.buf.signature_help() end, desc = "Signature help", cond = "textDocument/signatureHelp" }

M.n["gT"] = {
  function() vim.lsp.buf.type_definition() end,
  desc = "Definition of current type",
  cond = "textDocument/typeDefinition",
}

M.n["<leader>lG"] =
  { function() vim.lsp.buf.workspace_symbol() end, desc = "Search workspace symbols", cond = "workspace/symbol" }

M.n["<leader>uY"] = {
  function()
    vim.b.semantic_tokens_enabled = not vim.b.semantic_tokens_enabled
    for _, client in ipairs((vim.lsp.get_clients or vim.lsp.get_active_clients)()) do
      if client.server_capabilities.semanticTokensProvider then
        vim.lsp.semantic_tokens[vim.b.semantic_tokens_enabled and "start" or "stop"](0, client.id)
        vim.notify(("Buffer lsp semantic highlighting %s"):format(vim.b.semantic_tokens_enabled and "on" or "off"))
      end
    end
  end,
  desc = "Toggle LSP semantic highlight (buffer)",
  cond = "textDocument/semanticTokens/full",
}

-- TODO: FIX this
-- if not vim.tbl_isempty(M.v) then M.v["<leader>l"] = { desc = " LSP" } end

if vim.fn.exists ":LspInfo" > 0 then M.n["<leader>li"] = { "<cmd>LspInfo<cr>", desc = "LSP information" } end
--
if vim.fn.exists ":NullLsInfo" > 0 then M.n["<leader>lI"] = { "<cmd>NullLsInfo<cr>", desc = "Null-ls information" } end

if vim.fn.exists ":Telescope" > 0 or pcall(require, "telescope") then -- setup telescope mappings if available
  M.n["<leader>lD"] = { function() require("telescope.builtin").diagnostics() end, desc = "Search diagnostics" }
  if M.n.gd then M.n.gd[1] = function() require("telescope.builtin").lsp_definitions() end end
  if M.n.gI then M.n.gI[1] = function() require("telescope.builtin").lsp_implementations() end end
  if M.n.gr then M.n.gr[1] = function() require("telescope.builtin").lsp_references() end end
  if M.n["<leader>lR"] then M.n["<leader>lR"][1] = function() require("telescope.builtin").lsp_references() end end
  if M.n.gT then M.n.gT[1] = function() require("telescope.builtin").lsp_type_definitions() end end
  if M.n["<leader>lG"] then
    M.n["<leader>lG"][1] = function()
      vim.ui.input({ prompt = "Symbol Query: " }, function(query)
        if query then require("telescope.builtin").lsp_workspace_symbols { query = query } end
      end)
    end
  end
end

return M

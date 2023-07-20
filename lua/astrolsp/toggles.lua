local M = {}

local config = require("astrolsp").config
local features = config.features

local notify = vim.notify
local function bool2str(bool) return bool and "on" or "off" end

--- Toggle auto format
function M.autoformat()
  features.autoformat = not features.autoformat
  vim.notify(string.format("Global autoformatting %s", bool2str(features.autoformat)))
end

--- Toggle buffer local auto format
---@param bufnr? number The buffer to toggle the autoformatting of, default the current buffer
function M.buffer_autoformat(bufnr)
  bufnr = bufnr or 0
  local old_val = vim.b[bufnr].autoformat
  if old_val == nil then old_val = features.autoformat end
  vim.b[bufnr].autoformat = not old_val
  notify(string.format("Buffer autoformatting %s", bool2str(vim.b[bufnr].autoformat)))
end

--- Toggle buffer LSP inlay hints
---@param bufnr? number the buffer to toggle the clients on
function M.buffer_inlay_hints(bufnr)
  bufnr = bufnr or 0
  vim.b[bufnr].inlay_hints = not vim.b[bufnr].inlay_hints
  -- TODO: remove check after dropping support for Neovim v0.9
  if vim.lsp.inlay_hint then
    vim.lsp.inlay_hint(bufnr, vim.b[bufnr].inlay_hints)
    notify(string.format("Inlay hints %s", bool2str(vim.b[bufnr].inlay_hints)))
  end
end

--- Toggle buffer semantic token highlighting for all language servers that support it
---@param bufnr? number the buffer to toggle the clients on
function M.buffer_semantic_tokens(bufnr)
  bufnr = bufnr or 0
  vim.b[bufnr].semantic_tokens = not vim.b[bufnr].semantic_tokens
  for _, client in ipairs((vim.lsp.get_clients or vim.lsp.get_active_clients)()) do
    if client.server_capabilities.semanticTokensProvider then
      vim.lsp.semantic_tokens[vim.b[bufnr].semantic_tokens and "start" or "stop"](bufnr, client.id)
      notify(string.format("Buffer lsp semantic highlighting %s", bool2str(vim.b[bufnr].semantic_tokens)))
    end
  end
end

--- Toggle codelens
function M.codelens()
  features.codelens = not features.codelens
  if not features.codelens then vim.lsp.codelens.clear() end
  notify(string.format("CodeLens %s", bool2str(features.codelens)))
end

--- Toggle diagnostics
function M.diagnostics()
  features.diagnostics_mode = (features.diagnostics_mode - 1) % 4
  vim.diagnostic.config(require("astrolsp").diagnostics[features.diagnostics_mode])
  if features.diagnostics_mode == 0 then
    notify "diagnostics off"
  elseif features.diagnostics_mode == 1 then
    notify "only status diagnostics"
  elseif features.diagnostics_mode == 2 then
    notify "virtual text off"
  else
    notify "all diagnostics on"
  end
end

return M

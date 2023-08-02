--- ### AstroNvim LSP Toggles
--
-- Utility functions for easy LSP toggles
--
-- This module can be loaded with `local ui = require("astrolsp.toggles")`
--
-- @module astrolsp.toggles
-- @see astrolsp
-- @copyright 2023
-- @license GNU General Public License v3.0

local M = {}

local features = require("astrolsp").config.features

local function ui_notify(silent, ...) return not silent and vim.notify(...) end
local function bool2str(bool) return bool and "on" or "off" end

--- Toggle auto format
---@param silent? boolean if true then don't sent a notification
function M.autoformat(silent)
  features.autoformat = not features.autoformat
  ui_notify(silent, string.format("Global autoformatting %s", bool2str(features.autoformat)))
end

--- Toggle buffer local auto format
---@param bufnr? number The buffer to toggle the autoformatting of, default the current buffer
---@param silent? boolean if true then don't sent a notification
function M.buffer_autoformat(bufnr, silent)
  bufnr = bufnr or 0
  local old_val = vim.b[bufnr].autoformat
  if old_val == nil then old_val = features.autoformat end
  vim.b[bufnr].autoformat = not old_val
  ui_notify(silent, string.format("Buffer autoformatting %s", bool2str(vim.b[bufnr].autoformat)))
end

--- Toggle buffer LSP inlay hints
---@param bufnr? number the buffer to toggle the clients on
---@param silent? boolean if true then don't sent a notification
function M.buffer_inlay_hints(bufnr, silent)
  bufnr = bufnr or 0
  vim.b[bufnr].inlay_hints = not vim.b[bufnr].inlay_hints
  -- TODO: remove check after dropping support for Neovim v0.9
  if vim.lsp.inlay_hint then
    vim.lsp.inlay_hint(bufnr, vim.b[bufnr].inlay_hints)
    ui_notify(silent, string.format("Inlay hints %s", bool2str(vim.b[bufnr].inlay_hints)))
  end
end

--- Toggle buffer semantic token highlighting for all language servers that support it
---@param bufnr? number the buffer to toggle the clients on
---@param silent? boolean if true then don't sent a notification
function M.buffer_semantic_tokens(bufnr, silent)
  bufnr = bufnr or 0
  vim.b[bufnr].semantic_tokens = not vim.b[bufnr].semantic_tokens
  local toggled = false
  for _, client in ipairs(vim.lsp.get_clients { bufnr = bufnr }) do
    if client.server_capabilities.semanticTokensProvider then
      vim.lsp.semantic_tokens[vim.b[bufnr].semantic_tokens and "start" or "stop"](bufnr, client.id)
      toggled = true
    end
  end
  ui_notify(
    not toggled or silent,
    string.format("Buffer lsp semantic highlighting %s", bool2str(vim.b[bufnr].semantic_tokens))
  )
end

--- Toggle codelens
---@param silent? boolean if true then don't sent a notification
function M.codelens(silent)
  features.codelens = not features.codelens
  if not features.codelens then vim.lsp.codelens.clear() end
  ui_notify(silent, string.format("CodeLens %s", bool2str(features.codelens)))
end

--- Toggle diagnostics
---@param silent? boolean if true then don't sent a notification
function M.diagnostics(silent)
  features.diagnostics_mode = (features.diagnostics_mode - 1) % 4
  vim.diagnostic.config(require("astrolsp").diagnostics[features.diagnostics_mode])
  if features.diagnostics_mode == 0 then
    ui_notify(silent, "diagnostics off")
  elseif features.diagnostics_mode == 1 then
    ui_notify(silent, "only status diagnostics")
  elseif features.diagnostics_mode == 2 then
    ui_notify(silent, "virtual text off")
  else
    ui_notify(silent, "all diagnostics on")
  end
end

return M

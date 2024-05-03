---AstroNvim LSP Toggles
---
---Utility functions for easy LSP toggles
---
---This module can be loaded with `local ui = require("astrolsp.toggles")`
---
---copyright 2023
---license GNU General Public License v3.0
---@class astrolsp.toggles
local M = {}

local config = require("astrolsp").config
local features = config.features --[[@as AstroLSPFeatureOpts]]
local format_on_save = config.formatting.format_on_save --[[@as AstroLSPFormatOnSaveOpts]]

local function ui_notify(silent, ...) return not silent and vim.notify(...) end
local function bool2str(bool) return bool and "on" or "off" end

--- Toggle auto format
---@param silent? boolean if true then don't sent a notification
function M.autoformat(silent)
  format_on_save.enabled = not format_on_save.enabled
  ui_notify(silent, ("Global autoformatting %s"):format(bool2str(format_on_save.enabled)))
end

--- Toggle buffer local auto format
---@param bufnr? integer The buffer to toggle the autoformatting of, default the current buffer
---@param silent? boolean if true then don't sent a notification
function M.buffer_autoformat(bufnr, silent)
  bufnr = bufnr or 0
  local old_val = vim.b[bufnr].autoformat
  if old_val == nil then
    ui_notify(silent, "No LSP attached with auto formatting")
    return
  end
  vim.b[bufnr].autoformat = not old_val
  ui_notify(silent, ("Buffer autoformatting %s"):format(bool2str(vim.b[bufnr].autoformat)))
end

--- Toggle buffer LSP inlay hints
---@param bufnr? integer the buffer to toggle the clients on
---@param silent? boolean if true then don't sent a notification
function M.buffer_inlay_hints(bufnr, silent)
  if vim.lsp.inlay_hint then
    local filter = { bufnr = bufnr or 0 }
    vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled(filter), filter)
    ui_notify(silent, ("Buffer inlay hints %s"):format(bool2str(vim.lsp.inlay_hint.is_enabled(filter))))
  end
end

--- Toggle global LSP inlay hints
---@param silent? boolean if true then don't sent a notification
function M.inlay_hints(silent)
  if vim.lsp.inlay_hint then
    vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled())
    ui_notify(silent, ("Global inlay hints %s"):format(bool2str(vim.lsp.inlay_hint.is_enabled())))
  end
end

--- Toggle buffer semantic token highlighting for all language servers that support it
---@param bufnr? integer the buffer to toggle the clients on
---@param silent? boolean if true then don't sent a notification
function M.buffer_semantic_tokens(bufnr, silent)
  bufnr = bufnr or 0
  vim.b[bufnr].semantic_tokens = not vim.b[bufnr].semantic_tokens
  local toggled = false
  -- TODO: remove check after dropping support for Neovim v0.9
  ---@diagnostic disable-next-line: deprecated
  for _, client in ipairs((vim.lsp.get_clients or vim.lsp.get_active_clients) { bufnr = bufnr }) do
    if client.server_capabilities.semanticTokensProvider then
      vim.lsp.semantic_tokens[vim.b[bufnr].semantic_tokens and "start" or "stop"](bufnr, client.id)
      toggled = true
    end
  end
  ui_notify(
    not toggled or silent,
    ("Buffer lsp semantic highlighting %s"):format(bool2str(vim.b[bufnr].semantic_tokens))
  )
end

--- Toggle codelens
---@param silent? boolean if true then don't sent a notification
function M.codelens(silent)
  features.codelens = not features.codelens
  if not features.codelens then vim.lsp.codelens.clear() end
  ui_notify(silent, ("CodeLens %s"):format(bool2str(features.codelens)))
end

return M

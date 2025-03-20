---Utilities for interacting with the Neovim LSP integration
---
---This module can be loaded with `local astrolsp_utils = require "astrolsp.utils"`
---
---copyright 2025
---license GNU General Public License v3.0
---@class astrolsp.utils
local M = {}

-- TODO: remove helper functions when dropping support for Neovim v0.10

--- Helper function to support deprecated supports_method usage
---@param client vim.lsp.Client
---@param method string
---@param bufnr? integer
function M.supports_method(client, method, bufnr)
  if vim.fn.has "nvim-0.11" == 1 then
    return client:supports_method(method, bufnr)
  else
    ---@diagnostic disable-next-line: param-type-mismatch
    return client.supports_method(method, { bufnr = bufnr })
  end
end

--- Helper function to support deprecated request_sync usage
---@param client vim.lsp.Client
---@param req string
---@param params table
---@param timeout? integer
---@param bufnr? integer
function M.request_sync(client, req, params, timeout, bufnr)
  if vim.fn.has "nvim-0.11" == 1 then
    return client:request_sync(req, params, timeout, bufnr)
  else
    ---@diagnostic disable-next-line: param-type-mismatch
    return client.request_sync(req, params, timeout, bufnr)
  end
end

--- Helper function to support deprecated notify usage
---@param client vim.lsp.Client
---@param method string
---@param params? table
function M.notify(client, method, params)
  if vim.fn.has "nvim-0.11" == 1 then
    return client:notify(method, params)
  else
    ---@diagnostic disable-next-line: param-type-mismatch
    return client.notify(method, params)
  end
end

return M

---AstroNvim LSP File Operation Utilities
---
---Utilities for working with LSP based file operations
---
---This module is heavily inspired by nvim-lsp-file-operations
---https://github.com/antosha417/nvim-lsp-file-operations/tree/master
---
---This module can be loaded with `local astrolsp_fileops = require "astrolsp.file_operations"`
---
---copyright 2025
---license GNU General Public License v3.0
---@class astrolsp.file_operations
local M = {}

local config = vim.tbl_get(require "astrolsp", "config", "file_operations") or {}

-- TODO: remove check when dropping support for Neovim v0.9
local get_clients = vim.lsp.get_clients or vim.lsp.get_active_clients

---@class AstroLSPFileOperationsRename
---@field from string the original filename
---@field to string the new filename

local filter_cache = {}
local match_filters = function(filters, name)
  local fname = vim.fn.fnamemodify(name, ":p")
  for _, filter in pairs(filters) do
    if not filter_cache[filter] then filter_cache[filter] = {} end
    if filter_cache[filter][fname] == nil then
      local matched = false
      local pattern = filter.pattern
      local match_type = pattern.matches
      local is_dir = string.sub(fname, #fname) == "/"
      if not match_type or (match_type == "folder" and is_dir) or (match_type == "file" and not is_dir) then
        local regex = vim.fn.glob2regpat(pattern.glob)
        if vim.tbl_get(pattern, "options", "ignorecase") then regex = "\\c" .. regex end
        local previous_ignorecase = vim.o.ignorecase
        vim.o.ignorecase = false
        matched = vim.fn.match(fname, regex) ~= -1
        vim.o.ignorecase = previous_ignorecase
      end
      filter_cache[filter][fname] = matched
    end
    if filter_cache[filter][fname] then return true end
  end
  return false
end

--- Notify LSP clients that file(s) were created
---@param fnames string|string[] a file or list of files that were created
function M.didCreateFiles(fnames)
  if not vim.tbl_get(config, "operations", "didCreate") then return end
  for _, client in pairs(get_clients()) do
    local did_create = vim.tbl_get(client, "server_capabilities", "workspace", "fileOperations", "didCreate")
    if did_create then
      if type(fnames) == "string" then fnames = { fnames } end
      local filters = did_create.filters or {}
      local filtered = vim.tbl_filter(function(fname) return match_filters(filters, fname) end, fnames)
      if next(filtered) then
        client.notify(
          "workspace/didCreateFiles",
          { files = vim.tbl_map(function(fname) return { uri = vim.uri_from_fname(fname) } end, filtered) }
        )
      end
    end
  end
end

--- Notify LSP clients that file(s) were deleted
---@param fnames string|string[] a file or list of files that were deleted
function M.didDeleteFiles(fnames)
  if not vim.tbl_get(config, "operations", "didDelete") then return end
  for _, client in pairs(get_clients()) do
    local did_delete = vim.tbl_get(client, "server_capabilities", "workspace", "fileOperations", "didDelete")
    if did_delete ~= nil then
      if type(fnames) == "string" then fnames = { fnames } end
      local filters = did_delete.filters or {}
      local filtered = vim.tbl_filter(function(fname) return match_filters(filters, fname) end, fnames)
      if next(filtered) then
        client.notify(
          "workspace/didDeleteFiles",
          { files = vim.tbl_map(function(fname) return { uri = vim.uri_from_fname(fname) } end, filtered) }
        )
      end
    end
  end
end

--- Notify LSP clients that file(s) were renamed
---@param renames AstroLSPFileOperationsRename|AstroLSPFileOperationsRename[] a table or list of tables of files that were renamed
function M.didRenameFiles(renames)
  if not vim.tbl_get(config, "operations", "didRename") then return end
  for _, client in pairs(get_clients()) do
    local did_rename = vim.tbl_get(client, "server_capabilities", "workspace", "fileOperations", "didRename")
    if did_rename ~= nil then
      if renames.from then renames = { renames } end
      local filters = did_rename.filters or {}
      local filtered = vim.tbl_filter(
        function(rename) return rename.from and rename.to and match_filters(filters, rename.from) end,
        renames
      )
      if next(filtered) then
        client.notify("workspace/didRenameFiles", {
          files = vim.tbl_map(
            function(rename) return { oldUri = vim.uri_from_fname(rename.from), newUri = vim.uri_from_fname(rename.to) } end,
            filtered
          ),
        })
      end
    end
  end
end

local getWorkspaceEdit = function(client, req, params)
  local success, resp = pcall(client.request_sync, req, params, config.timeout)
  if success then return resp.result end
end

--- Notify LSP clients that file(s) are going to be created
---@param fnames string|string[] a file or list of files that will be created
function M.willCreateFiles(fnames)
  if not vim.tbl_get(config, "operations", "willCreate") then return end
  for _, client in pairs(get_clients()) do
    local will_create = vim.tbl_get(client, "server_capabilities", "workspace", "fileOperations", "willCreate")
    if will_create then
      if type(fnames) == "string" then fnames = { fnames } end
      local filters = will_create.filters or {}
      local filtered = vim.tbl_filter(function(fname) return match_filters(filters, fname) end, fnames)
      if next(filtered) then
        local edit = getWorkspaceEdit(
          client,
          "workspace/didCreateFiles",
          { files = vim.tbl_map(function(fname) return { uri = vim.uri_from_fname(fname) } end, filtered) }
        )
        if edit then vim.lsp.util.apply_workspace_edit(edit, client.offset_encoding) end
      end
    end
  end
end

--- Notify LSP clients that file(s) are going to be deleted
---@param fnames string|string[] a file or list of files that will be deleted
function M.willDeleteFiles(fnames)
  if not vim.tbl_get(config, "operations", "willDelete") then return end
  for _, client in pairs(get_clients()) do
    local will_delete = vim.tbl_get(client, "server_capabilities", "workspace", "fileOperations", "willDelete")
    if will_delete then
      if type(fnames) == "string" then fnames = { fnames } end
      local filters = will_delete.filters or {}
      local filtered = vim.tbl_filter(function(fname) return match_filters(filters, fname) end, fnames)
      if next(filtered) then
        local edit = getWorkspaceEdit(
          client,
          "workspace/willDeleteFiles",
          { files = vim.tbl_map(function(fname) return { uri = vim.uri_from_fname(fname) } end, filtered) }
        )
        if edit then vim.lsp.util.apply_workspace_edit(edit, client.offset_encoding) end
      end
    end
  end
end

--- Notify LSP clients that file(s) are going to be renamed
---@param renames AstroLSPFileOperationsRename|AstroLSPFileOperationsRename[] a table or list of tables of files that will be renamed
function M.willRenameFiles(renames)
  if not vim.tbl_get(config, "operations", "willRename") then return end
  for _, client in pairs(get_clients()) do
    local will_rename = vim.tbl_get(client, "server_capabilities", "workspace", "fileOperations", "willRename")
    if will_rename then
      if renames.from then renames = { renames } end
      local filters = will_rename.filters or {}
      local filtered = vim.tbl_filter(
        function(rename) return rename.from and rename.to and match_filters(filters, rename.from) end,
        renames
      )
      if next(filtered) then
        local edit = getWorkspaceEdit(client, "workspace/willRenameFiles", {
          files = vim.tbl_map(
            function(rename) return { oldUri = vim.uri_from_fname(rename.from), newUri = vim.uri_from_fname(rename.to) } end,
            filtered
          ),
        })
        if edit then vim.lsp.util.apply_workspace_edit(edit, client.offset_encoding) end
      end
    end
  end
end

return M

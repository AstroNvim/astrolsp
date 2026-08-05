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

local function get_config() return vim.tbl_get(require "astrolsp", "config", "file_operations") or {} end

---@class AstroLSPFileOperationsRename
---@field from string|AstroLSPFileOperationPath the original filename
---@field to string|AstroLSPFileOperationPath the new filename
---@field kind? "file"|"folder" the renamed item's kind

---@class AstroLSPFileOperationPath
---@field path string the file or folder path
---@field kind? "file"|"folder" the path's kind

local function normalize_path(path)
  if type(path) == "string" then return { path = path } end
  return path
end

local function normalize_paths(paths)
  if type(paths) == "string" or paths.path then return { normalize_path(paths) } end
  return vim.tbl_map(normalize_path, paths)
end

local function normalize_renames(renames)
  if renames.from then renames = { renames } end
  return vim.tbl_map(function(rename)
    local from, to = normalize_path(rename.from), normalize_path(rename.to)
    return {
      from = from.path,
      to = to.path,
      kind = rename.kind or from.kind or to.kind,
    }
  end, renames)
end

local filter_cache = {}
local match_filters = function(filters, file)
  local fname = vim.fn.fnamemodify(file.path, ":p")
  local cache_key = fname .. "\0" .. (file.kind or "")
  for _, filter in pairs(filters) do
    if not filter_cache[filter] then filter_cache[filter] = {} end
    if filter_cache[filter][cache_key] == nil then
      local scheme = filter.scheme
      local matched = false
      local pattern = filter.pattern
      local match_type = pattern.matches
      local is_dir = file.kind == "folder" or (file.kind == nil and string.sub(fname, #fname) == "/")
      if
        (not scheme or scheme:lower() == "file")
        and (not match_type or (match_type == "folder" and is_dir) or (match_type == "file" and not is_dir))
      then
        local regex = vim.fn.glob2regpat(pattern.glob)
        if vim.tbl_get(pattern, "options", "ignoreCase") then regex = "\\c" .. regex end
        local previous_ignorecase = vim.o.ignorecase
        vim.o.ignorecase = false
        matched = vim.fn.match(fname, regex) ~= -1
        vim.o.ignorecase = previous_ignorecase
      end
      filter_cache[filter][cache_key] = matched
    end
    if filter_cache[filter][cache_key] then return true end
  end
  return false
end

--- Notify LSP clients that file(s) were created
---@param fnames string|AstroLSPFileOperationPath|(string|AstroLSPFileOperationPath)[] a file or list of files that were created
function M.didCreateFiles(fnames)
  local config = get_config()
  if not vim.tbl_get(config, "operations", "didCreate") then return end
  local paths = normalize_paths(fnames)
  for _, client in pairs(vim.lsp.get_clients()) do
    local did_create = vim.tbl_get(client, "server_capabilities", "workspace", "fileOperations", "didCreate")
    if did_create then
      local filters = did_create.filters or {}
      local filtered = vim.tbl_filter(function(path) return match_filters(filters, path) end, paths)
      if next(filtered) then
        client:notify(
          "workspace/didCreateFiles",
          { files = vim.tbl_map(function(path) return { uri = vim.uri_from_fname(path.path) } end, filtered) }
        )
      end
    end
  end
end

--- Notify LSP clients that file(s) were deleted
---@param fnames string|AstroLSPFileOperationPath|(string|AstroLSPFileOperationPath)[] a file or list of files that were deleted
function M.didDeleteFiles(fnames)
  local config = get_config()
  if not vim.tbl_get(config, "operations", "didDelete") then return end
  local paths = normalize_paths(fnames)
  for _, client in pairs(vim.lsp.get_clients()) do
    local did_delete = vim.tbl_get(client, "server_capabilities", "workspace", "fileOperations", "didDelete")
    if did_delete ~= nil then
      local filters = did_delete.filters or {}
      local filtered = vim.tbl_filter(function(path) return match_filters(filters, path) end, paths)
      if next(filtered) then
        client:notify(
          "workspace/didDeleteFiles",
          { files = vim.tbl_map(function(path) return { uri = vim.uri_from_fname(path.path) } end, filtered) }
        )
      end
    end
  end
end

--- Notify LSP clients that file(s) were renamed
---@param renames AstroLSPFileOperationsRename|AstroLSPFileOperationsRename[] a table or list of tables of files that were renamed
function M.didRenameFiles(renames)
  local config = get_config()
  if not vim.tbl_get(config, "operations", "didRename") then return end
  local normalized_renames = normalize_renames(renames)
  for _, client in pairs(vim.lsp.get_clients()) do
    local did_rename = vim.tbl_get(client, "server_capabilities", "workspace", "fileOperations", "didRename")
    if did_rename ~= nil then
      local filters = did_rename.filters or {}
      local filtered = vim.tbl_filter(
        function(rename)
          return rename.from and rename.to and match_filters(filters, { path = rename.from, kind = rename.kind })
        end,
        normalized_renames
      )
      if next(filtered) then
        client:notify("workspace/didRenameFiles", {
          files = vim.tbl_map(
            function(rename) return { oldUri = vim.uri_from_fname(rename.from), newUri = vim.uri_from_fname(rename.to) } end,
            filtered
          ),
        })
      end
    end
  end
end

---@param client vim.lsp.Client
---@param req string
---@param params table
---@param timeout integer?
local function getWorkspaceEdit(client, req, params, timeout)
  local resp = client:request_sync(req, params, timeout)
  if resp and resp.result then return resp.result end
end

--- Request workspace edits from LSP clients before file(s) are created
---@param fnames string|AstroLSPFileOperationPath|(string|AstroLSPFileOperationPath)[] a file or list of files that will be created
function M.willCreateFiles(fnames)
  local config = get_config()
  if not vim.tbl_get(config, "operations", "willCreate") then return end
  local paths = normalize_paths(fnames)
  for _, client in pairs(vim.lsp.get_clients()) do
    local will_create = vim.tbl_get(client, "server_capabilities", "workspace", "fileOperations", "willCreate")
    if will_create then
      local filters = will_create.filters or {}
      local filtered = vim.tbl_filter(function(path) return match_filters(filters, path) end, paths)
      if next(filtered) then
        local edit = getWorkspaceEdit(
          client,
          "workspace/willCreateFiles",
          { files = vim.tbl_map(function(path) return { uri = vim.uri_from_fname(path.path) } end, filtered) },
          config.timeout
        )
        if edit then vim.lsp.util.apply_workspace_edit(edit, client.offset_encoding) end
      end
    end
  end
end

--- Request workspace edits from LSP clients before file(s) are deleted
---@param fnames string|AstroLSPFileOperationPath|(string|AstroLSPFileOperationPath)[] a file or list of files that will be deleted
function M.willDeleteFiles(fnames)
  local config = get_config()
  if not vim.tbl_get(config, "operations", "willDelete") then return end
  local paths = normalize_paths(fnames)
  for _, client in pairs(vim.lsp.get_clients()) do
    local will_delete = vim.tbl_get(client, "server_capabilities", "workspace", "fileOperations", "willDelete")
    if will_delete then
      local filters = will_delete.filters or {}
      local filtered = vim.tbl_filter(function(path) return match_filters(filters, path) end, paths)
      if next(filtered) then
        local edit = getWorkspaceEdit(
          client,
          "workspace/willDeleteFiles",
          { files = vim.tbl_map(function(path) return { uri = vim.uri_from_fname(path.path) } end, filtered) },
          config.timeout
        )
        if edit then vim.lsp.util.apply_workspace_edit(edit, client.offset_encoding) end
      end
    end
  end
end

--- Request workspace edits from LSP clients before file(s) are renamed
---@param renames AstroLSPFileOperationsRename|AstroLSPFileOperationsRename[] a table or list of tables of files that will be renamed
function M.willRenameFiles(renames)
  local config = get_config()
  if not vim.tbl_get(config, "operations", "willRename") then return end
  local normalized_renames = normalize_renames(renames)
  for _, client in pairs(vim.lsp.get_clients()) do
    local will_rename = vim.tbl_get(client, "server_capabilities", "workspace", "fileOperations", "willRename")
    if will_rename then
      local filters = will_rename.filters or {}
      local filtered = vim.tbl_filter(
        function(rename)
          return rename.from and rename.to and match_filters(filters, { path = rename.from, kind = rename.kind })
        end,
        normalized_renames
      )
      if next(filtered) then
        local edit = getWorkspaceEdit(client, "workspace/willRenameFiles", {
          files = vim.tbl_map(
            function(rename) return { oldUri = vim.uri_from_fname(rename.from), newUri = vim.uri_from_fname(rename.to) } end,
            filtered
          ),
        }, config.timeout)
        if edit then vim.lsp.util.apply_workspace_edit(edit, client.offset_encoding) end
      end
    end
  end
end

return M

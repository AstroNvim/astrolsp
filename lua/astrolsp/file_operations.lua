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

local normalize_lsp = require("astrolsp.utils").normalize

local function get_registrations(client, operation, method)
  if vim.fn.has "nvim-0.13" == 1 then
    return client.dynamic_capabilities:get("workspace.fileOperations." .. operation) or {}
  end

  -- TODO: remove this compatibility block when dropping support for Neovim v0.12
  if client._get_registrations then return client:_get_registrations "workspace" or {} end
  return client.registrations[method] or {}
end

local function add_filters(filters, options)
  options = normalize_lsp(options)
  if type(options) ~= "table" or type(options.filters) ~= "table" then return end
  for _, filter in ipairs(options.filters) do
    filters[#filters + 1] = filter
  end
end

local function get_operation(client, operation)
  local method = "workspace/" .. operation .. "Files"
  local filters = {}
  add_filters(filters, vim.tbl_get(client, "server_capabilities", "workspace", "fileOperations", operation))
  for _, registration in ipairs(get_registrations(client, operation, method)) do
    if registration.method == method then add_filters(filters, registration.registerOptions) end
  end
  if #filters == 0 then return end
  return { filters = filters }
end

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

local function get_match_path(file)
  local fname = vim.fn.fnamemodify(file.path, ":p")
  if vim.fn.has "win32" == 1 then fname = fname:gsub("\\", "/") end

  local is_dir
  if file.kind == "folder" then
    is_dir = true
  elseif file.kind == "file" then
    is_dir = false
  else
    is_dir = vim.fn.isdirectory(file.path) == 1 or string.sub(fname, -1) == "/"
  end

  if is_dir and string.sub(fname, -1) ~= "/" then
    fname = fname .. "/"
  elseif not is_dir and string.sub(fname, -1) == "/" and #fname > 1 then
    fname = string.sub(fname, 1, -2)
  end
  return fname, is_dir
end

local function matches_filter(filter, fname, is_dir)
  if type(filter) ~= "table" or type(filter.pattern) ~= "table" then return false end

  local scheme = filter.scheme
  local pattern = filter.pattern
  local match_type = pattern.matches
  if
    (not scheme or (type(scheme) == "string" and scheme:lower() == "file"))
    and (not match_type or (match_type == "folder" and is_dir) or (match_type == "file" and not is_dir))
    and type(pattern.glob) == "string"
  then
    local glob, path = pattern.glob, fname
    if vim.tbl_get(pattern, "options", "ignoreCase") then
      glob, path = glob:lower(), path:lower()
    end

    local ok, matched = pcall(function() return vim.glob.to_lpeg(glob):match(path) ~= nil end)
    return ok and matched or false
  end
  return false
end

local function match_filters(filters, file)
  local fname, is_dir = get_match_path(file)
  for _, filter in pairs(filters) do
    if matches_filter(filter, fname, is_dir) then return true end
  end
  return false
end

local function notify_client(client, method, params)
  pcall(function() client:notify(method, params) end)
end

--- Notify LSP clients that file(s) were created
---@param fnames string|AstroLSPFileOperationPath|(string|AstroLSPFileOperationPath)[] a file or list of files that were created
function M.didCreateFiles(fnames)
  local config = get_config()
  if not vim.tbl_get(config, "operations", "didCreate") then return end
  local paths = normalize_paths(fnames)
  for _, client in pairs(vim.lsp.get_clients()) do
    local did_create = get_operation(client, "didCreate")
    if did_create then
      local filters = did_create.filters or {}
      local filtered = vim.tbl_filter(function(path) return match_filters(filters, path) end, paths)
      if next(filtered) then
        notify_client(
          client,
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
    local did_delete = get_operation(client, "didDelete")
    if did_delete ~= nil then
      local filters = did_delete.filters or {}
      local filtered = vim.tbl_filter(function(path) return match_filters(filters, path) end, paths)
      if next(filtered) then
        notify_client(
          client,
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
    local did_rename = get_operation(client, "didRename")
    if did_rename ~= nil then
      local filters = did_rename.filters or {}
      local filtered = vim.tbl_filter(
        function(rename)
          return rename.from and rename.to and match_filters(filters, { path = rename.from, kind = rename.kind })
        end,
        normalized_renames
      )
      if next(filtered) then
        notify_client(client, "workspace/didRenameFiles", {
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
  local ok, resp = pcall(function() return client:request_sync(req, params, timeout) end)
  if ok and resp and resp.result then return resp.result end
end

--- Request workspace edits from LSP clients before file(s) are created
---@param fnames string|AstroLSPFileOperationPath|(string|AstroLSPFileOperationPath)[] a file or list of files that will be created
function M.willCreateFiles(fnames)
  local config = get_config()
  if not vim.tbl_get(config, "operations", "willCreate") then return end
  local paths = normalize_paths(fnames)
  for _, client in pairs(vim.lsp.get_clients()) do
    local will_create = get_operation(client, "willCreate")
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
    local will_delete = get_operation(client, "willDelete")
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
    local will_rename = get_operation(client, "willRename")
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

---Utilities for working with mason-lspconfig.nvim
---
---This module can be loaded with `local astrolsp_mason_lspconfig = require "astrolsp.mason-lspconfig"`
---
---copyright 2025
---license GNU General Public License v3.0
---@class astrolsp.mason-lspconfig
local M = {}

local function resolve_config() return require("astrolsp").config.mason_lspconfig or {} end

--- Register a new language server with mason-lspconfig
---@param server string the server name in lspconfig
---@param spec AstroLSPMasonLspconfigServer the details for registering the server
function M.register_server(server, spec)
  local filetype_mappings_avail, filetype_mappings = pcall(require, "mason-lspconfig.mappings.filetype")
  local server_mappings_avail, server_mappings = pcall(require, "mason-lspconfig.mappings.server")

  if not (filetype_mappings_avail and server_mappings_avail) then
    vim.notify("Unable to properly load required `mason-lspconfig` modules", vim.log.levels.ERROR)
  end

  -- register server in the filetype maps
  local filetypes = spec.filetypes
  if type(filetypes) ~= "table" then filetypes = { filetypes } end
  for _, filetype in ipairs(filetypes) do
    if not filetype_mappings[filetype] then filetype_mappings[filetype] = {} end
    table.insert(filetype_mappings, server)
  end
  -- register the mappings between lspconfig server name and mason package name
  server_mappings.lspconfig_to_package[server] = spec.package
  server_mappings.package_to_lspconfig[spec.package] = server
  -- if a config is provided, set up a mason-lspconfig server configuration module
  if spec.config then
    local module = spec.config
    if type(module) == "table" then
      local orig_function = module
      module = function() return orig_function end
    end
    local module_name = "mason-lspconfig.server_configurations." .. server
    if package.loaded[module_name] == nil then
      package.preload[module_name] = function() return module end
    else
      package.loaded[module_name] = module
    end
  end
end

--- Register multiple new language servers with mason-lspconfig
---@param server_specs? AstroLSPMasonLspconfigServers
function M.register_servers(server_specs)
  if not server_specs then server_specs = resolve_config().servers or {} end
  for server, spec in pairs(server_specs) do
    M.register_server(server, spec)
  end
end

return M

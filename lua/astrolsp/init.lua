---AstroNvim LSP Utilities
---
---Various utility functions to use within AstroNvim for the LSP engine
---
---This module can be loaded with `local astro = require "astrolsp"`
---
---copyright 2023
---license GNU General Public License v3.0
---@class astrolsp
local M = {}

local tbl_contains = vim.tbl_contains
local tbl_isempty = vim.tbl_isempty

--- The configuration as set by the user through the `setup()` function
M.config = require "astrolsp.config"
--- A table of lsp progress messages that can be used to display LSP progress in a statusline
M.lsp_progress = {}

local function lsp_event(name)
  vim.schedule(function() vim.api.nvim_exec_autocmds("User", { pattern = "AstroLsp" .. name, modeline = false }) end)
end

---@param cond AstroLSPCondition?
---@param client lsp.Client
---@param bufnr integer
local function check_cond(cond, client, bufnr)
  local active = true
  if type(cond) == "function" then
    active = cond(client, bufnr)
  elseif type(cond) == "string" then
    active = client.supports_method(cond)
  elseif type(cond) == "boolean" then
    active = cond
  end
  return active
end

--- A table of settings for different levels of diagnostics
M.diagnostics = { [0] = {}, {}, {}, {} }

local function setup_diagnostics()
  if M.config.signs then vim.fn.sign_define(M.config.signs) end
  M.diagnostics = {
    -- diagnostics off
    [0] = vim.tbl_deep_extend(
      "force",
      M.config.diagnostics,
      { underline = false, virtual_text = false, signs = false, update_in_insert = false }
    ),
    -- status only
    vim.tbl_deep_extend("force", M.config.diagnostics, { virtual_text = false, signs = false }),
    -- virtual text off, signs on
    vim.tbl_deep_extend("force", M.config.diagnostics, { virtual_text = false }),
    -- all diagnostics on
    M.config.diagnostics,
  }

  vim.diagnostic.config(M.diagnostics[M.config.features.diagnostics_mode])
end

--- Helper function to set up a given server with the Neovim LSP client
---@param server string The name of the server to be setup
function M.lsp_setup(server)
  -- if server doesn't exist, set it up from user server definition
  local config_avail, config = pcall(require, "lspconfig.server_configurations." .. server)
  if not config_avail or not config.default_config then
    local server_definition = M.config.config[server]
    if server_definition and server_definition.cmd then
      require("lspconfig.configs")[server] = { default_config = server_definition }
    end
  end
  local opts = M.lsp_opts(server)
  local handler = M.config.handlers[server]
  if handler == nil then handler = M.config.handlers[1] end
  if handler then
    handler(server, opts)
  elseif handler == nil then
    require("lspconfig")[server].setup(opts)
  end
end

--- The `on_attach` function used by AstroNvim
---@param client table The LSP client details when attaching
---@param bufnr integer The buffer that the LSP client is attaching to
M.on_attach = function(client, bufnr)
  if client.supports_method "textDocument/codeLens" and M.config.features.codelens then vim.lsp.codelens.refresh() end

  local formatting_disabled = vim.tbl_get(M.config, "formatting", "disabled")
  if
    client.supports_method "textDocument/formatting"
    and (formatting_disabled ~= true and not tbl_contains(formatting_disabled, client.name))
  then
    local autoformat = assert(M.config.formatting.format_on_save)
    local filetype = vim.bo[bufnr].filetype
    if vim.b[bufnr].autoformat == nil then
      vim.b[bufnr].autoformat = autoformat.enabled
        and (tbl_isempty(autoformat.allow_filetypes or {}) or tbl_contains(autoformat.allow_filetypes, filetype))
        and (tbl_isempty(autoformat.ignore_filetypes or {}) or not tbl_contains(autoformat.ignore_filetypes, filetype))
    end
  end

  if client.supports_method "textDocument/inlayHint" then
    if vim.b[bufnr].inlay_hints == nil then vim.b[bufnr].inlay_hints = M.config.features.inlay_hints end
    -- TODO: remove check after dropping support for Neovim v0.9
    if vim.lsp.inlay_hint and vim.b[bufnr].inlay_hints then vim.lsp.inlay_hint.enable(bufnr, true) end
  end

  if client.supports_method "textDocument/semanticTokens/full" and vim.lsp.semantic_tokens then
    if M.config.features.semantic_tokens then
      vim.b[bufnr].semantic_tokens = true
    else
      client.server_capabilities.semanticTokensProvider = nil
    end
  end

  -- user commands
  for cmd, spec in pairs(M.config.commands) do
    if spec then
      local cond = spec.cond
      if check_cond(cond, client, bufnr) then
        local action = spec[1]
        spec[1], spec.cond = nil, nil
        vim.api.nvim_buf_create_user_command(bufnr, cmd, action, spec)
        spec[1], spec.cond = action, cond
      end
    end
  end

  for augroup, autocmds in pairs(M.config.autocmds) do
    if autocmds then
      local cmds_found, cmds = pcall(vim.api.nvim_get_autocmds, { group = augroup, buffer = bufnr })
      if not cmds_found or vim.tbl_isempty(cmds) then
        local cond = autocmds.cond
        if check_cond(cond, client, bufnr) then
          local group = vim.api.nvim_create_augroup(augroup, { clear = false })
          for _, autocmd in ipairs(autocmds) do
            local callback, command, event = autocmd.callback, autocmd.command, autocmd.event
            autocmd.command, autocmd.event = nil, nil
            autocmd.group, autocmd.buffer = group, bufnr
            local callback_func = command and function(_, _, _) vim.cmd(command) end or callback
            autocmd.callback = function(args)
              local invalid = true
              for _, cb_client in ipairs((vim.lsp.get_clients or vim.lsp.get_active_clients) { buffer = bufnr }) do
                if check_cond(cond, cb_client, bufnr) then
                  invalid = false
                  break
                end
              end
              if invalid then
                local cb_cmds_found, cb_cmds = pcall(vim.api.nvim_get_autocmds, { group = augroup, buffer = bufnr })
                if cb_cmds_found then vim.tbl_map(function(cmd) vim.api.nvim_del_autocmd(cmd.id) end, cb_cmds) end
              else
                callback_func(args, client, bufnr)
              end
            end
            vim.api.nvim_create_autocmd(event, autocmd)
            autocmd.callback, autocmd.command, autocmd.event = callback, command, event
            autocmd.group, autocmd.buffer = nil, nil
          end
        end
      end
    end
  end

  local wk_avail, wk = pcall(require, "which-key")
  for mode, maps in pairs(M.config.mappings) do
    for lhs, map_opts in pairs(maps) do
      if map_opts then
        local active = map_opts ~= false
        if type(map_opts) == "table" then active = check_cond(map_opts.cond, client, bufnr) end
        if active then
          local rhs
          if type(map_opts) == "string" then
            rhs = map_opts
            map_opts = { buffer = bufnr }
          else
            rhs = map_opts[1]
            map_opts = assert(vim.tbl_deep_extend("force", map_opts, { buffer = bufnr }))
            map_opts[1], map_opts.cond = nil, nil
          end
          if not rhs or map_opts.name then
            if not map_opts.name then map_opts.name = map_opts.desc end
            if wk_avail then wk.register({ [lhs] = map_opts }, { mode = mode }) end
          else
            vim.keymap.set(mode, lhs, rhs, map_opts)
          end
        end
      end
    end
  end

  for id, _ in pairs(M.lsp_progress) do -- clear lingering progress messages
    -- TODO: remove check after dropping support for Neovim v0.9
    ---@diagnostic disable-next-line: deprecated
    if not next((vim.lsp.get_clients or vim.lsp.get_active_clients) { id = tonumber(id:match "^%d+") }) then
      M.lsp_progress[id] = nil
    end
  end

  if type(M.config.on_attach) == "function" then M.config.on_attach(client, bufnr) end
end

--- Get the server configuration for a given language server to be provided to the server's `setup()` call
---@param server_name string The name of the server
---@return table # The table of LSP options used when setting up the given language server
function M.lsp_opts(server_name)
  if server_name == "lua_ls" then pcall(require, "neodev") end
  local opts = { capabilities = M.config.capabilities, flags = M.config.flags }
  if M.config.config[server_name] then opts = vim.tbl_deep_extend("force", opts, M.config.config[server_name]) end
  assert(opts)

  local old_on_attach = require("lspconfig.configs")[server_name] and require("lspconfig")[server_name].on_attach
  local user_on_attach = opts.on_attach
  opts.on_attach = function(client, bufnr)
    if type(old_on_attach) == "function" then old_on_attach(client, bufnr) end
    M.on_attach(client, bufnr)
    if type(user_on_attach) == "function" then user_on_attach(client, bufnr) end
  end
  return opts
end

--- Setup and configure AstroLSP
---@param opts AstroLSPOpts options passed by the user to configure AstroLSP
function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts)

  -- TODO: Remove when dropping support for Neovim v0.9
  -- Backwards compatibility of new diagnostic sign API to Neovim v0.9
  if vim.fn.has "nvim-0.10" ~= 1 then
    local diagnostic_text = vim.tbl_get(M.config, "diagnostics", "signs", "text") or {}
    if not M.config.signs then M.config.signs = {} end
    for _, type in ipairs { "Error", "Hint", "Info", "Warn" } do
      local name = "DiagnosticSign" .. type
      table.insert(M.config.signs, {
        name = name,
        text = diagnostic_text[vim.diagnostic.severity[type:upper()]],
        texthl = name,
      })
    end
  end

  setup_diagnostics()

  -- normalize format_on_save to table format
  if vim.tbl_get(M.config, "formatting", "format_on_save") == false then
    M.config.formatting.format_on_save = { enabled = false }
  end

  --- Format options that are passed into the `vim.lsp.buf.format` (`:h vim.lsp.buf.format()`)
  ---@type AstroLSPFormatOpts
  M.format_opts = vim.deepcopy(assert(M.config.formatting))
  M.format_opts.disabled = nil
  M.format_opts.format_on_save = nil
  M.format_opts.filter = function(client)
    local filter = M.config.formatting.filter
    local disabled = M.config.formatting.disabled or {}
    -- check if client is fully disabled or filtered by function
    return disabled ~= true
      and not (vim.tbl_contains(disabled, client.name) or (type(filter) == "function" and not filter(client)))
  end

  local orig_handler = vim.lsp.handlers["$/progress"]
  vim.lsp.handlers["$/progress"] = function(_, msg, info)
    local progress, id = M.lsp_progress, ("%s.%s"):format(info.client_id, msg.token)
    progress[id] = progress[id] and vim.tbl_deep_extend("force", progress[id], msg.value) or msg.value
    if progress[id].kind == "end" then
      vim.defer_fn(function()
        progress[id] = nil
        lsp_event "Progress"
      end, 100)
    end
    lsp_event "Progress"
    orig_handler(_, msg, info)
  end

  if M.config.features.lsp_handlers then
    vim.lsp.handlers["textDocument/hover"] = vim.lsp.with(vim.lsp.handlers.hover, { border = "rounded", silent = true })
    vim.lsp.handlers["textDocument/signatureHelp"] =
      vim.lsp.with(vim.lsp.handlers.signature_help, { border = "rounded", silent = true })
  end
end

return M

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
--- A table of LSP clients that have been attached with AstroLSP
M.attached_clients = {}

local function lsp_event(name) vim.api.nvim_exec_autocmds("User", { pattern = "AstroLsp" .. name, modeline = false }) end

---@param cond AstroLSPCondition?
---@param client vim.lsp.Client
---@param bufnr integer
local function check_cond(cond, client, bufnr)
  local cond_type = type(cond)
  if cond_type == "function" then return cond(client, bufnr) end
  if cond_type == "string" then return client.supports_method(cond) end
  if cond_type == "boolean" then return cond end
  return true
end

--- Add a new LSP progress message to the message queue
---@param data {client_id: integer, params: lsp.ProgressParams}
function M.progress(data)
  local id = ("%s.%s"):format(data.client_id, data.params.token)
  M.lsp_progress[id] = M.lsp_progress[id] and vim.tbl_deep_extend("force", M.lsp_progress[id], data.params.value)
    or data.params.value
  if M.lsp_progress[id].kind == "end" then
    vim.defer_fn(function()
      M.lsp_progress[id] = nil
      lsp_event "Progress"
    end, 100)
  end
  lsp_event "Progress"
end

--- Helper function to set up a given server with the Neovim LSP client
---@param server string The name of the server to be setup
function M.lsp_setup(server)
  -- if server doesn't exist, set it up from user server definition
  local lspconfig_avail, lspconfig = pcall(require, "lspconfig")
  if lspconfig_avail then
    local config_avail, config = pcall(require, "lspconfig.server_configurations." .. server)
    if not config_avail or not config.default_config then
      local server_definition = M.config.config[server]
      if server_definition and server_definition.cmd then
        require("lspconfig.configs")[server] = { default_config = server_definition }
      end
    end
  end
  local opts = M.lsp_opts(server)
  local handler = M.config.handlers[server]
  if handler == nil then handler = M.config.handlers[1] end
  if handler then
    handler(server, opts)
  elseif handler == nil then
    if lspconfig_avail then
      lspconfig[server].setup(opts)
    else
      vim.notify(("No handler defined for `%s`"):format(server), vim.log.levels.WARN)
    end
  end
end

--- The `on_attach` function used by AstroNvim
---@param client vim.lsp.Client The LSP client details when attaching
---@param bufnr integer The buffer that the LSP client is attaching to
function M.on_attach(client, bufnr)
  if client.supports_method "textDocument/codeLens" and M.config.features.codelens then
    vim.lsp.codelens.refresh { bufnr = bufnr }
  end

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

  if client.supports_method "textDocument/semanticTokens/full" and vim.lsp.semantic_tokens then
    if M.config.features.semantic_tokens then
      if vim.b[bufnr].semantic_tokens == nil then vim.b[bufnr].semantic_tokens = true end
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
              return invalid or callback_func(args, client, bufnr)
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
          if rhs then
            vim.keymap.set(mode, lhs, rhs, map_opts --[[@as vim.keymap.set.Opts]])
          elseif wk_avail then
            map_opts[1], map_opts.mode = lhs, mode
            if not map_opts.group then map_opts.group = map_opts.desc end
            wk.add(map_opts)
          end
        end
      end
    end
  end

  if type(M.config.on_attach) == "function" then M.config.on_attach(client, bufnr) end

  if not M.attached_clients[client.id] then M.attached_clients[client.id] = client end
end

--- Get the server configuration for a given language server to be provided to the server's `setup()` call
---@param server_name string The name of the server
---@return table # The table of LSP options used when setting up the given language server
function M.lsp_opts(server_name)
  local opts = { capabilities = M.config.capabilities, flags = M.config.flags }
  if M.config.config[server_name] then opts = vim.tbl_deep_extend("force", opts, M.config.config[server_name]) end
  assert(opts)

  local lspconfig_avail, lspconfig = pcall(require, "lspconfig")
  local old_on_attach = lspconfig_avail
    and require("lspconfig.configs")[server_name]
    and lspconfig[server_name].on_attach
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

  -- TODO: remove check when dropping support for Neovim v0.9
  if vim.lsp.inlay_hint then vim.lsp.inlay_hint.enable(M.config.features.inlay_hints ~= false) end

  -- Set up tracking of signature help trigger characters
  local augroup = vim.api.nvim_create_augroup("track_signature_help_triggers", { clear = true })
  vim.api.nvim_create_autocmd("LspAttach", {
    group = augroup,
    desc = "Add signature help triggers as language servers attach",
    callback = function(args)
      local client = vim.lsp.get_client_by_id(args.data.client_id)
      if client and client.supports_method "textDocument/signatureHelp" then
        vim.b[args.buf].signature_help_trigger = require("astrocore").list_insert_unique(
          vim.b[args.buf].signature_help_trigger,
          client.server_capabilities.signatureHelpProvider.triggerCharacters or {}
        )
      end
    end,
  })
  vim.api.nvim_create_autocmd("LspDetach", {
    group = augroup,
    desc = "Safely remove LSP signature help triggers when language servers detach",
    callback = vim.schedule_wrap(function(args)
      if not vim.api.nvim_buf_is_valid(args.buf) then return end
      local signature_help_trigger = {}
      for _, client in pairs((vim.lsp.get_clients or vim.lsp.get_active_clients) { bufnr = args.buf }) do
        if client.id ~= args.data.client_id and client.supports_method "textDocument/signatureHelp" then
          require("astrocore").list_insert_unique(
            signature_help_trigger,
            client.server_capabilities.signatureHelpProvider.triggerCharacters or {}
          )
        end
      end
      vim.b[args.buf].signature_help_trigger = signature_help_trigger
    end),
  })

  vim.api.nvim_create_autocmd("LspDetach", {
    group = vim.api.nvim_create_augroup("astrolsp_detach", { clear = true }),
    desc = "Clear state when language server is detached like LSP progress messages",
    callback = function(args)
      M.attached_clients[args.data.client_id] = nil
      local changed = false
      for id, _ in pairs(M.lsp_progress) do -- clear lingering progress messages
        if tonumber(id:match "^%d+") == args.data.client_id then
          M.lsp_progress[id] = nil
          changed = true
        end
      end
      if changed then lsp_event "Progress" end
    end,
  })

  local ok = pcall(vim.api.nvim_create_autocmd, "LspProgress", {
    group = vim.api.nvim_create_augroup("astrolsp_progress", { clear = true }),
    desc = "Collect LSP progress messages for later handling",
    callback = function(event) M.progress(event.data) end,
  })
  if not ok then
    local progress_handler = vim.lsp.handlers["$/progress"]
    vim.lsp.handlers["$/progress"] = function(err, res, ctx)
      M.progress { client_id = ctx.client_id, params = res }
      progress_handler(err, res, ctx)
    end
  end

  local register_capability_handler = vim.lsp.handlers["client/registerCapability"]
  vim.lsp.handlers["client/registerCapability"] = function(err, res, ctx)
    local ret = register_capability_handler(err, res, ctx)
    local attached_client = M.attached_clients[ctx.client_id]
    if attached_client then M.on_attach(attached_client, vim.api.nvim_get_current_buf()) end
    return ret
  end

  for method, handler in pairs(M.config.lsp_handlers or {}) do
    if handler then vim.lsp.handlers[method] = handler end
  end
end

return M

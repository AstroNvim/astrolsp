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

local function lsp_event(name, data)
  vim.api.nvim_exec_autocmds("User", { pattern = "AstroLsp" .. name, modeline = false, data = data })
end

---@param cond? AstroLSPCondition
---@param client vim.lsp.Client
---@param bufnr integer
local function check_cond(cond, client, bufnr)
  local cond_type = type(cond)
  if cond_type == "function" then return cond(client, bufnr) end
  if cond_type == "string" then return client:supports_method(cond, bufnr) end
  if cond_type == "boolean" then return cond end
  return true
end

--- Check whether autoformatting is enabled for a buffer
---@param bufnr? integer The buffer to check, default the current buffer
---@return boolean enabled Whether autoformatting is enabled
function M.autoformat_enabled(bufnr)
  bufnr = bufnr or 0
  local buffer_autoformat = vim.b[bufnr].autoformat
  if buffer_autoformat ~= nil then return buffer_autoformat end

  local autoformat = assert(M.config.formatting.format_on_save)
  if type(autoformat) == "boolean" then return autoformat end
  local filetype = vim.bo[bufnr].filetype
  return autoformat.enabled == true
    and (type(autoformat.filter) ~= "function" or autoformat.filter(bufnr))
    and (tbl_isempty(autoformat.allow_filetypes or {}) or tbl_contains(autoformat.allow_filetypes, filetype))
    and (tbl_isempty(autoformat.ignore_filetypes or {}) or not tbl_contains(autoformat.ignore_filetypes, filetype))
end

--- Check whether a buffer has an LSP client available for autoformatting
---@param bufnr? integer The buffer to check, default the current buffer
---@return boolean available Whether autoformatting can be toggled for the buffer
function M.autoformat_available(bufnr)
  bufnr = bufnr or 0
  local formatting_disabled = M.config.formatting.disabled or {}
  if formatting_disabled == true then return false end
  for _, client in pairs(vim.lsp.get_clients { bufnr = bufnr }) do
    if
      client:supports_method("textDocument/formatting", bufnr) and not tbl_contains(formatting_disabled, client.name)
    then
      return true
    end
  end
  return false
end

--- Add a new LSP progress message to the message queue
---@param data {client_id: integer, params: lsp.ProgressParams}
function M.progress(data)
  local id = ("%s.%s.%s"):format(data.client_id, type(data.params.token), data.params.token)
  local value = data.params.value
  if type(value) == "table" then
    for key, val in pairs(value) do
      if val == vim.NIL then value[key] = nil end
    end
  end
  local progress
  if not value or value.kind == "begin" then
    progress = value
  elseif M.lsp_progress[id] then
    progress = vim.tbl_deep_extend("force", M.lsp_progress[id], value)
  else
    progress = value
  end
  M.lsp_progress[id] = progress
  if not progress or progress.kind == "end" then
    vim.defer_fn(function()
      if M.lsp_progress[id] == progress then
        M.lsp_progress[id] = nil
        lsp_event "Progress"
      end
    end, 100)
  end
  lsp_event "Progress"
end

--- Helper function to set up a given server with the Neovim LSP client
---@param server string The name of the server to be setup
function M.lsp_setup(server)
  local handler = vim.F.if_nil(M.config.handlers[server], M.config.handlers["*"], vim.lsp.enable)
  if handler then handler(server) end
end

--- Set up a given `on_attach` function to run when language servers are attached
---@param on_attach fun(client:vim.lsp.Client, bufnr:integer) the `on_attach` function to run
---@param opts? { client_name: string?, autocmd: vim.api.keyset.create_autocmd? } options for configuring the `on_attach`
---@return integer autocmd_id The id for the created LspAttach autocommand
function M.add_on_attach(on_attach, opts)
  if not opts then opts = {} end
  local client_name, autocmd_opts = opts.client_name, opts.autocmd or {}
  return vim.api.nvim_create_autocmd(
    "LspAttach",
    vim.tbl_deep_extend("force", autocmd_opts, {
      callback = function(args)
        local client = vim.lsp.get_client_by_id(args.data.client_id)
        if client and (not client_name or client_name == client.name) then return on_attach(client, args.buf) end
      end,
    })
  )
end

local function configure_buffer(client, bufnr)
  -- TODO: remove check when dropping support for Neovim v0.11
  if
    client:supports_method("textDocument/codeLens", bufnr)
    and not vim.lsp.codelens.enable
    and M.config.features.codelens
  then
    vim.lsp.codelens.refresh { bufnr = bufnr }
  end

  -- TODO: remove when dropping support for Neovim v0.11
  if client:supports_method("textDocument/semanticTokens/full", bufnr) and not vim.lsp.semantic_tokens.enable then
    if M.config.features.semantic_tokens == false then
      client.server_capabilities.semanticTokensProvider = nil
    elseif vim.b[bufnr].semantic_tokens == nil then
      vim.b[bufnr].semantic_tokens = true
    elseif vim.b[bufnr].semantic_tokens == false then
      vim.schedule(function()
        vim.schedule(function()
          if vim.api.nvim_buf_is_valid(bufnr) and vim.b[bufnr].semantic_tokens == false then
            pcall(vim.lsp.semantic_tokens.stop, bufnr, client.id)
          end
        end)
      end)
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
            ---@cast callback_func function
            autocmd.callback = function(args)
              local callback_client
              for _, cb_client in ipairs(vim.lsp.get_clients { bufnr = bufnr }) do
                if check_cond(cond, cb_client, bufnr) then
                  callback_client = cb_client
                  break
                end
              end
              if callback_client then return callback_func(args, callback_client, bufnr) end
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
          ---@cast map_opts AstroLSPMapping
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
end

--- The `on_attach` function used by AstroNvim
---@param client vim.lsp.Client The LSP client details when attaching
---@param bufnr integer The buffer that the LSP client is attaching to
function M.on_attach(client, bufnr)
  configure_buffer(client, bufnr)
  if type(M.config.on_attach) == "function" then M.config.on_attach(client, bufnr) end
  if not M.attached_clients[client.id] then M.attached_clients[client.id] = client end
end

local key_cache = {} ---@type { [string]: string }

---@param mappings AstroLSPMappings?
local function normalize_mappings(mappings)
  if not mappings then return end
  for _, mode_maps in pairs(mappings) do
    for key, _ in pairs(mode_maps) do
      if not key_cache[key] then
        key_cache[key] = vim.fn.keytrans(vim.api.nvim_replace_termcodes(key, true, true, true))
      end
      local normkey = key_cache[key]
      if key ~= normkey then
        mode_maps[normkey], mode_maps[key] = mode_maps[key], nil
      end
    end
  end
end

local function unique_list(...)
  local out, found = {}, {}
  for _, tbl in ipairs { ... } do
    for _, i in ipairs(tbl) do
      if not found[i] then
        found[i] = true
        table.insert(out, i)
      end
    end
  end
  return out
end

--- Setup and configure AstroLSP
---@param opts AstroLSPOpts options passed by the user to configure AstroLSP
function M.setup(opts)
  normalize_mappings(M.config.mappings)
  normalize_mappings(opts.mappings)
  -- TODO: remove when dropping support for Neoivm v0.11
  if vim.fn.has "nvim-0.12" == 1 then
    ---@diagnostic disable-next-line: param-type-mismatch
    M.config = vim.tbl_deep_extend(function(key, prev_value, value)
      if key == "servers" then
        if type(value) == "table" and type(prev_value) == "table" then return unique_list(prev_value, value) end
      end
      return value
    end, M.config, opts)
  else
    M.config = vim.tbl_deep_extend("force", M.config, opts)
    M.config.servers = unique_list(M.config.servers)
  end

  -- enable necessary capabilities for enabled LSP file operations
  local fileOperations = vim.tbl_get(M.config, "file_operations", "operations")
  if fileOperations and not vim.tbl_isempty(fileOperations) then
    M.config.config = vim.tbl_deep_extend("force", M.config.config or {}, {
      ["*"] = {
        capabilities = { workspace = { fileOperations = fileOperations } },
      },
    })
  end

  for server, config in pairs(M.config.config) do
    vim.lsp.config(server, config)
  end

  -- Set up tracking of signature help trigger characters
  M.add_on_attach(M.on_attach, {
    autocmd = {
      group = vim.api.nvim_create_augroup("astrolsp_on_attach", { clear = true }),
      desc = "AstroLSP on_attach function",
    },
  })

  local rename_augroup = vim.api.nvim_create_augroup("astrolsp_rename_operations", { clear = true })
  vim.api.nvim_create_autocmd("User", {
    group = rename_augroup,
    desc = "trigger willRenameFiles LSP operation on AstroCore file rename",
    pattern = "AstroRenameFilePre",
    callback = function(args) require("astrolsp.file_operations").willRenameFiles(args.data) end,
  })
  vim.api.nvim_create_autocmd("User", {
    group = rename_augroup,
    desc = "trigger didRenameFiles LSP operation on AstroCore file rename",
    pattern = "AstroRenameFilePost",
    callback = function(args)
      if args.data.success then require("astrolsp.file_operations").didRenameFiles(args.data) end
    end,
  })

  -- normalize boolean format_on_save values to table format
  local format_on_save = vim.tbl_get(M.config, "formatting", "format_on_save")
  if type(format_on_save) == "boolean" then M.config.formatting.format_on_save = { enabled = format_on_save } end

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

  vim.lsp.inlay_hint.enable(M.config.features.inlay_hints ~= false)
  -- TODO: remove check when dropping support for Neovim v0.11
  if vim.lsp.semantic_tokens.enable then vim.lsp.semantic_tokens.enable(M.config.features.semantic_tokens ~= false) end
  if vim.lsp.linked_editing_range then
    vim.lsp.linked_editing_range.enable(M.config.features.linked_editing_range ~= false)
  end
  -- TODO: remove check when dropping support for Neovim v0.11
  if vim.lsp.codelens.enable then vim.lsp.codelens.enable(M.config.features.codelens ~= false) end
  -- TODO: remove check when dropping support for Neovim v0.11
  if vim.lsp.inline_completion then vim.lsp.inline_completion.enable(M.config.features.inline_completion ~= false) end

  -- Set up tracking of signature help trigger characters
  -- TODO: remove this helper and the `else` fallback below when dropping support for Neovim v0.11
  local function registration_applies(client, registration, bufnr)
    local options = registration.registerOptions
    if type(options) ~= "table" or type(options.documentSelector) ~= "table" then return true end
    local language = client._get_language_id and client:_get_language_id(bufnr) or vim.bo[bufnr].filetype
    local uri = vim.uri_from_bufnr(bufnr)
    local filename = vim.uri_to_fname(uri)
    for _, filter in ipairs(options.documentSelector) do
      if
        not (filter.language and language ~= filter.language)
        and not (filter.scheme and not vim.startswith(uri, filter.scheme .. ":"))
        and not (type(filter.pattern) == "string" and not vim.glob.to_lpeg(filter.pattern):match(filename))
      then
        return true
      end
    end
    return false
  end

  local function refresh_signature_help_triggers(bufnr, excluded_client_id)
    if not vim.api.nvim_buf_is_valid(bufnr) then return end
    local triggers, retriggers = {}, {}
    local function add_options(options)
      if type(options) ~= "table" then return end
      for _, trigger in ipairs(options.triggerCharacters or {}) do
        triggers[trigger] = true
      end
      for _, retrigger in ipairs(options.retriggerCharacters or {}) do
        retriggers[retrigger] = true
      end
    end
    for _, client in pairs(vim.lsp.get_clients { bufnr = bufnr }) do
      if client.id ~= excluded_client_id and client:supports_method("textDocument/signatureHelp", bufnr) then
        add_options(client.server_capabilities.signatureHelpProvider)
        if client._get_registrations then
          for _, registration in ipairs(client:_get_registrations("signatureHelpProvider", bufnr) or {}) do
            add_options(registration.registerOptions)
          end
        else
          for _, registration in ipairs(client.registrations["textDocument/signatureHelp"] or {}) do
            if registration_applies(client, registration, bufnr) then add_options(registration.registerOptions) end
          end
        end
      end
    end
    vim.b[bufnr].signature_help_triggerCharacters = triggers
    vim.b[bufnr].signature_help_retriggerCharacters = retriggers
  end

  local augroup = vim.api.nvim_create_augroup("track_signature_help_triggers", { clear = true })
  M.add_on_attach(function(_, bufnr) refresh_signature_help_triggers(bufnr) end, {
    autocmd = {
      group = augroup,
      desc = "Add signature help triggers as language servers attach",
    },
  })
  vim.api.nvim_create_autocmd("LspDetach", {
    group = augroup,
    desc = "Safely remove LSP signature help triggers when language servers detach",
    callback = function(args) refresh_signature_help_triggers(args.buf, args.data.client_id) end,
  })

  vim.api.nvim_create_autocmd("LspDetach", {
    group = vim.api.nvim_create_augroup("astrolsp_detach", { clear = true }),
    desc = "Clear state when language server is detached like LSP progress messages",
    callback = function(args)
      local client = vim.lsp.get_client_by_id(args.data.client_id)
      if client then
        for bufnr, _ in pairs(client.attached_buffers) do
          if bufnr ~= args.buf then return end
        end
      end
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
    local client = vim.lsp.get_client_by_id(ctx.client_id)
    if client then
      for bufnr, _ in pairs(client.attached_buffers) do
        configure_buffer(client, bufnr)
        refresh_signature_help_triggers(bufnr)
        lsp_event("Capability", { client_id = client.id, bufnr = bufnr })
      end
    end
    return ret
  end

  local unregister_capability_handler = vim.lsp.handlers["client/unregisterCapability"]
  vim.lsp.handlers["client/unregisterCapability"] = function(err, res, ctx)
    local ret = unregister_capability_handler(err, res, ctx)
    local client = vim.lsp.get_client_by_id(ctx.client_id)
    if client then
      for bufnr, _ in pairs(client.attached_buffers) do
        refresh_signature_help_triggers(bufnr)
        lsp_event("Capability", { client_id = client.id, bufnr = bufnr })
      end
    end
    return ret
  end

  for method, default in pairs(M.config.defaults) do
    if default then
      local original_method = vim.lsp.buf[method]
      if type(original_method) == "function" then
        vim.lsp.buf[method] = function(user_opts)
          return original_method(vim.tbl_deep_extend("force", default, user_opts or {}))
        end
      end
    end
  end

  for method, handler in pairs(M.config.lsp_handlers or {}) do
    if handler then vim.lsp.handlers[method] = handler end
  end

  vim.tbl_map(M.lsp_setup, M.config.servers)
end

return M

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

--- Add a new LSP progress message to the message queue
---@param data {client_id: integer, params: lsp.ProgressParams}
function M.progress(data)
  local id = ("%s.%s"):format(data.client_id, data.params.token)
  M.lsp_progress[id] = M.lsp_progress[id] and vim.tbl_deep_extend("force", M.lsp_progress[id], data.params.value)
    or data.params.value
  if not M.lsp_progress[id] or M.lsp_progress[id].kind == "end" then
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

--- The `on_attach` function used by AstroNvim
---@param client vim.lsp.Client The LSP client details when attaching
---@param bufnr integer The buffer that the LSP client is attaching to
function M.on_attach(client, bufnr)
  if client:supports_method("textDocument/codeLens", bufnr) and M.config.features.codelens then
    vim.lsp.codelens.refresh { bufnr = bufnr }
  end

  local formatting_disabled = vim.tbl_get(M.config, "formatting", "disabled")
  if
    client:supports_method("textDocument/formatting", bufnr)
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

  -- TODO: remove when dropping support for Neovim v0.11
  if client:supports_method("textDocument/semanticTokens/full", bufnr) and not vim.lsp.semantic_tokens.enable then
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
              for _, cb_client in ipairs(vim.lsp.get_clients { buffer = bufnr }) do
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
  local extend_method = "force"
  if vim.fn.has "nvim-0.12" == 1 then
    extend_method = function(key, prev_value, value)
      if key == "servers" then
        if type(value) == "table" and type(prev_value) == "table" then return unique_list(prev_value, value) end
      end
      return value
    end
  end
  M.config = vim.tbl_deep_extend(extend_method, M.config, opts)

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

  vim.lsp.inlay_hint.enable(M.config.features.inlay_hints ~= false)
  -- TODO: remove check when dropping support for Neovim v0.11
  if vim.lsp.semantic_tokens.enable then vim.lsp.semantic_tokens.enable(M.config.features.semantic_tokens ~= false) end
  if vim.lsp.linked_editing_range then
    vim.lsp.linked_editing_range.enable(M.config.features.linked_editing_range ~= false)
  end

  -- Set up tracking of signature help trigger characters
  local augroup = vim.api.nvim_create_augroup("track_signature_help_triggers", { clear = true })
  M.add_on_attach(function(client, bufnr)
    if client:supports_method("textDocument/signatureHelp", bufnr) then
      for _, set in ipairs { "triggerCharacters", "retriggerCharacters" } do
        local set_var = "signature_help_" .. set
        local triggers = vim.b[bufnr][set_var] or {}
        for _, trigger in ipairs(client.server_capabilities.signatureHelpProvider[set] or {}) do
          triggers[trigger] = true
        end
        vim.b[bufnr][set_var] = triggers
      end
    end
  end, {
    autocmd = {
      group = augroup,
      desc = "Add signature help triggers as language servers attach",
    },
  })
  vim.api.nvim_create_autocmd("LspDetach", {
    group = augroup,
    desc = "Safely remove LSP signature help triggers when language servers detach",
    callback = function(args)
      if not vim.api.nvim_buf_is_valid(args.buf) then return end
      local triggers, retriggers = {}, {}
      for _, client in pairs(vim.lsp.get_clients { bufnr = args.buf }) do
        if client.id ~= args.data.client_id and client:supports_method("textDocument/signatureHelp", args.buf) then
          for _, trigger in ipairs(client.server_capabilities.signatureHelpProvider.triggerCharacters or {}) do
            triggers[trigger] = true
          end
          for _, retrigger in ipairs(client.server_capabilities.signatureHelpProvider.retriggerCharacters or {}) do
            retriggers[retrigger] = true
          end
        end
      end
      vim.b[args.buf].signature_help_triggerCharacters = triggers
      vim.b[args.buf].signature_help_retriggerCharacters = retriggers
    end,
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

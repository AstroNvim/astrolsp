local M = {}

M.lsp_progress = {}

function M.event(event)
  vim.schedule(function() vim.api.nvim_exec_autocmds("User", { pattern = "AstroLSP" .. event, modeline = false }) end)
end

function M.setup(opts)
  for section, default in pairs(require "astrolsp.config") do
    local opt = opts[section]
    if opt then
      if type(opt) == "function" then
        opts[section] = opt(default) or default
      elseif type(opt) == "table" then
        opts[section] = vim.tbl_deep_extend("force", default, opt)
      else
        vim.api.nvim_err_writeln(("AstroLSP: Invalid %s option"):format(section))
      end
    else
      opts[section] = default
    end
  end

  M.options = opts

  local orig_handler = vim.lsp.handlers["$/progress"]
  vim.lsp.handlers["$/progress"] = function(_, msg, info)
    local progress, id = M.lsp_progress, ("%s.%s"):format(info.client_id, msg.token)
    progress[id] = progress[id] and vim.tbl_deep_extend("force", progress[id], msg.value) or msg.value
    if progress[id].kind == "end" then
      vim.defer_fn(function()
        progress[id] = nil
        M.event "Progress"
      end, 100)
    end
    M.event "Progress"
    orig_handler(_, msg, info)
  end
end

local tbl_contains = vim.tbl_contains
local tbl_isempty = vim.tbl_isempty

M.diagnostics = { [0] = {}, {}, {}, {} }

M.setup_diagnostics = function()
  M.diagnostics = {
    -- diagnostics off
    [0] = vim.tbl_deep_extend(
      "force",
      M.options.diagnostics,
      { underline = false, virtual_text = false, signs = false, update_in_insert = false }
    ),
    -- status only
    vim.tbl_deep_extend("force", M.options.diagnostics, { virtual_text = false, signs = false }),
    -- virtual text off, signs on
    vim.tbl_deep_extend("force", M.options.diagnostics, { virtual_text = false }),
    -- all diagnostics on
    M.options.diagnostics,
  }

  vim.diagnostic.config(M.diagnostics[vim.g.diagnostics_mode])
end

M.format_opts = vim.deepcopy(M.options.formatting)
M.format_opts.disabled = nil
M.format_opts.format_on_save = nil
M.format_opts.filter = function(client)
  local filter = M.formatting.filter
  local disabled = M.formatting.disabled or {}
  -- check if client is fully disabled or filtered by function
  return not (vim.tbl_contains(disabled, client.name) or (type(filter) == "function" and not filter(client)))
end

--- Helper function to set up a given server with the Neovim LSP client
---@param server string The name of the server to be setup
M.lsp_setup = function(server)
  -- if server doesn't exist, set it up from user server definition
  local config_avail, config = pcall(require, "lspconfig.server_configurations." .. server)
  if not config_avail or not config.default_config then
    local server_definition = M.options.config[server]
    if server_definition.cmd then require("lspconfig.configs")[server] = { default_config = server_definition } end
  end
  local opts = M.config(server)
  local setup_handler = M.options.setup_handlers[server] or M.options.setup_handlers[1]
  if setup_handler then setup_handler(server, opts) end
end

--- Helper function to check if any active LSP clients given a filter provide a specific capability
---@param capability string The server capability to check for (example: "documentFormattingProvider")
---@param filter vim.lsp.get_active_clients.filter|nil (table|nil) A table with
---              key-value pairs used to filter the returned clients.
---              The available keys are:
---               - id (number): Only return clients with the given id
---               - bufnr (number): Only return clients attached to this buffer
---               - name (string): Only return clients with the given name
---@return boolean # Whether or not any of the clients provide the capability
function M.has_capability(capability, filter)
  for _, client in ipairs(vim.lsp.get_active_clients(filter)) do
    if client.supports_method(capability) then return true end
  end
  return false
end

local function add_buffer_autocmd(augroup, bufnr, autocmds)
  if not vim.tbl_islist(autocmds) then autocmds = { autocmds } end
  local cmds_found, cmds = pcall(vim.api.nvim_get_autocmds, { group = augroup, buffer = bufnr })
  if not cmds_found or vim.tbl_isempty(cmds) then
    vim.api.nvim_create_augroup(augroup, { clear = false })
    for _, autocmd in ipairs(autocmds) do
      local events = autocmd.events
      autocmd.events = nil
      autocmd.group = augroup
      autocmd.buffer = bufnr
      vim.api.nvim_create_autocmd(events, autocmd)
    end
  end
end

local function del_buffer_autocmd(augroup, bufnr)
  local cmds_found, cmds = pcall(vim.api.nvim_get_autocmds, { group = augroup, buffer = bufnr })
  if cmds_found then vim.tbl_map(function(cmd) vim.api.nvim_del_autocmd(cmd.id) end, cmds) end
end

--- The `on_attach` function used by AstroNvim
---@param client table The LSP client details when attaching
---@param bufnr number The buffer that the LSP client is attaching to
M.on_attach = function(client, bufnr)
  if client.supports_method "textDocument/codeLens" then
    add_buffer_autocmd("lsp_codelens_refresh", bufnr, {
      events = { "InsertLeave", "BufEnter" },
      desc = "Refresh codelens",
      callback = function()
        if not M.has_capability("textDocument/codeLens", { bufnr = bufnr }) then
          del_buffer_autocmd("lsp_codelens_refresh", bufnr)
          return
        end
        if vim.g.codelens_enabled then vim.lsp.codelens.refresh() end
      end,
    })
    if vim.g.codelens_enabled then vim.lsp.codelens.refresh() end
  end

  if client.supports_method "textDocument/formatting" and not tbl_contains(M.formatting.disabled, client.name) then
    vim.api.nvim_buf_create_user_command(
      bufnr,
      "Format",
      function() vim.lsp.buf.format(M.format_opts) end,
      { desc = "Format file with LSP" }
    )
    local autoformat = M.formatting.format_on_save
    local filetype = vim.api.nvim_get_option_value("filetype", { buf = bufnr })
    if
      autoformat.enabled
      and (tbl_isempty(autoformat.allow_filetypes or {}) or tbl_contains(autoformat.allow_filetypes, filetype))
      and (tbl_isempty(autoformat.ignore_filetypes or {}) or not tbl_contains(autoformat.ignore_filetypes, filetype))
    then
      add_buffer_autocmd("lsp_auto_format", bufnr, {
        events = "BufWritePre",
        desc = "autoformat on save",
        callback = function()
          if not M.has_capability("textDocument/formatting", { bufnr = bufnr }) then
            del_buffer_autocmd("lsp_auto_format", bufnr)
            return
          end
          local autoformat_enabled = vim.b.autoformat_enabled
          if autoformat_enabled == nil then autoformat_enabled = vim.g.autoformat_enabled end
          if autoformat_enabled and ((not autoformat.filter) or autoformat.filter(bufnr)) then
            vim.lsp.buf.format(vim.tbl_deep_extend("force", M.format_opts, { bufnr = bufnr }))
          end
        end,
      })
    end
  end

  if client.supports_method "textDocument/documentHighlight" then
    add_buffer_autocmd("lsp_document_highlight", bufnr, {
      {
        events = { "CursorHold", "CursorHoldI" },
        desc = "highlight references when cursor holds",
        callback = function()
          if not M.has_capability("textDocument/documentHighlight", { bufnr = bufnr }) then
            del_buffer_autocmd("lsp_document_highlight", bufnr)
            return
          end
          vim.lsp.buf.document_highlight()
        end,
      },
      {
        events = { "CursorMoved", "CursorMovedI" },
        desc = "clear references when cursor moves",
        callback = function() vim.lsp.buf.clear_references() end,
      },
    })
  end

  if client.supports_method "textDocument/inlayHint" then
    if vim.b.inlay_hints_enabled == nil then vim.b.inlay_hints_enabled = vim.g.inlay_hints_enabled end
    -- TODO: remove check after dropping support for Neovim v0.9
    if vim.lsp.inlay_hint then
      if vim.b.inlay_hints_enabled then vim.lsp.inlay_hint(bufnr, true) end
    end
  end

  if client.supports_method and vim.lsp.semantic_tokens then
    if vim.b.semantic_tokens_enabled == nil then vim.b.semantic_tokens_enabled = vim.g.semantic_tokens_enabled end
    if not vim.g.semantic_tokens_enabled then vim.lsp.semantic_tokens["stop"](bufnr, client.id) end
  end

  for mode, maps in pairs(M.options.mappings) do
    for lhs, map_opts in pairs(maps) do
      if
        map_opts.cond == nil
        or type(map_opts.cond) == "boolean" and map_opts.cond
        or type(map_opts.cond) == "function" and map_opts.cond(client, bufnr)
        or type(map_opts.cond) == "string" and client.supports_method(map_opts.cond)
      then
        local rhs = map_opts[1]
        map_opts[1], map_opts.cond = nil, nil
        map_opts.buffer = bufnr
        vim.keymap.set(mode, lhs, rhs, map_opts)
      end
    end
  end

  for id, _ in pairs(M.lsp_progress) do -- clear lingering progress messages
    if not next(vim.lsp.get_active_clients { id = tonumber(id:match "^%d+") }) then M.lsp_progress[id] = nil end
  end

  if type(M.options.on_attach) == "function" then M.options.on_attach(client, bufnr) end
end

--- Get the server configuration for a given language server to be provided to the server's `setup()` call
---@param server_name string The name of the server
---@return table # The table of LSP options used when setting up the given language server
function M.config(server_name)
  -- TODO: move to default configuration
  -- if server_name == "jsonls" then -- by default add json schemas
  --   local schemastore_avail, schemastore = pcall(require, "schemastore")
  --   if schemastore_avail then
  --     lsp_opts.settings = { json = { schemas = schemastore.json.schemas(), validate = { enable = true } } }
  --   end
  -- end
  -- if server_name == "yamlls" then -- by default add yaml schemas
  --   local schemastore_avail, schemastore = pcall(require, "schemastore")
  --   if schemastore_avail then lsp_opts.settings = { yaml = { schemas = schemastore.yaml.schemas() } } end
  -- end
  -- if server_name == "lua_ls" then -- by default initialize neodev and disable third party checking
  --   pcall(require, "neodev")
  --   lsp_opts.before_init = function(param, config)
  --     if vim.b.neodev_enabled then
  --       for _, astronvim_config in ipairs(astronvim.supported_configs) do
  --         if param.rootPath:match(astronvim_config) then
  --           table.insert(config.settings.Lua.workspace.library, astronvim.install.home .. "/lua")
  --           break
  --         end
  --       end
  --     end
  --   end
  --   lsp_opts.settings = { Lua = { workspace = { checkThirdParty = false } } }
  -- end
  local opts =
    vim.tbl_deep_extend("force", { capabilities = M.capabilities, flags = M.flags }, M.options.config[server_name])
  local old_on_attach = require("lspconfig")[server_name].on_attach
  local user_on_attach = opts.on_attach
  opts.on_attach = function(client, bufnr)
    if type(old_on_attach) == "function" then old_on_attach(client, bufnr) end
    M.on_attach(client, bufnr)
    if type(user_on_attach) == "function" then user_on_attach(client, bufnr) end
  end
  return opts
end

return M

local M = {}

local utils = require "astrolsp.utils"
local tbl_contains = vim.tbl_contains
local tbl_isempty = vim.tbl_isempty

M.lsp_progress = {}

function M.setup(opts)
  opts = opts or {}
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

  M.setup_diagnostics()

  M.format_opts = vim.deepcopy(M.options.formatting)
  M.format_opts.disabled = nil
  M.format_opts.format_on_save = nil
  M.format_opts.filter = function(client)
    local filter = M.options.formatting.filter
    local disabled = M.options.formatting.disabled or {}
    -- check if client is fully disabled or filtered by function
    return not (vim.tbl_contains(disabled, client.name) or (type(filter) == "function" and not filter(client)))
  end

  local orig_handler = vim.lsp.handlers["$/progress"]
  vim.lsp.handlers["$/progress"] = function(_, msg, info)
    local progress, id = M.lsp_progress, ("%s.%s"):format(info.client_id, msg.token)
    progress[id] = progress[id] and vim.tbl_deep_extend("force", progress[id], msg.value) or msg.value
    if progress[id].kind == "end" then
      vim.defer_fn(function()
        progress[id] = nil
        utils.event "Progress"
      end, 100)
    end
    utils.event "Progress"
    orig_handler(_, msg, info)
  end
end

M.diagnostics = { [0] = {}, {}, {}, {} }

function M.setup_diagnostics()
  for _, sign in ipairs(M.options.diagnostics.signs.active) do
    vim.fn.sign_define(sign.name, sign)
  end
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

--- Helper function to set up a given server with the Neovim LSP client
---@param server string The name of the server to be setup
function M.lsp_setup(server)
  -- HACK: add astronvim interoperability, remove after AstroNvim v4
  if type(astronvim) == "table" and type(astronvim.lsp) == "table" and type(astronvim.lsp.skip_setup) == "table" then
    if vim.tbl_contains(astronvim.lsp.skip_setup, server) then return end
  end
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

--- The `on_attach` function used by AstroNvim
---@param client table The LSP client details when attaching
---@param bufnr number The buffer that the LSP client is attaching to
M.on_attach = function(client, bufnr)
  if client.supports_method "textDocument/codeLens" then
    add_buffer_autocmd("lsp_codelens_refresh", bufnr, {
      events = { "InsertLeave", "BufEnter" },
      desc = "Refresh codelens",
      callback = function()
        if not utils.has_capability("textDocument/codeLens", { bufnr = bufnr }) then
          utils.del_buffer_autocmd("lsp_codelens_refresh", bufnr)
          return
        end
        if vim.g.codelens_enabled then vim.lsp.codelens.refresh() end
      end,
    })
    if vim.g.codelens_enabled then vim.lsp.codelens.refresh() end
  end

  if
    client.supports_method "textDocument/formatting" and not tbl_contains(M.options.formatting.disabled, client.name)
  then
    vim.api.nvim_buf_create_user_command(
      bufnr,
      "Format",
      function() vim.lsp.buf.format(M.format_opts) end,
      { desc = "Format file with LSP" }
    )
    local autoformat = M.options.formatting.format_on_save
    local filetype = vim.api.nvim_get_option_value("filetype", { buf = bufnr })
    if vim.b[bufnr].autoformat_enabled == nil then
      vim.b[bufnr].autoformat_enabled = autoformat.enabled
        and (tbl_isempty(autoformat.allow_filetypes or {}) or tbl_contains(autoformat.allow_filetypes, filetype))
        and (tbl_isempty(autoformat.ignore_filetypes or {}) or not tbl_contains(autoformat.ignore_filetypes, filetype))
    end
    add_buffer_autocmd("lsp_auto_format", bufnr, {
      events = "BufWritePre",
      desc = "autoformat on save",
      callback = function()
        if not utils.has_capability("textDocument/formatting", { bufnr = bufnr }) then
          utils.del_buffer_autocmd("lsp_auto_format", bufnr)
          return
        end
        local autoformat_enabled = vim.b[bufnr].autoformat_enabled
        if autoformat_enabled == nil then autoformat_enabled = autoformat.enabled end
        if autoformat_enabled and ((not autoformat.filter) or autoformat.filter(bufnr)) then
          vim.lsp.buf.format(vim.tbl_deep_extend("force", M.format_opts, { bufnr = bufnr }))
        end
      end,
    })
  end

  if client.supports_method "textDocument/documentHighlight" then
    add_buffer_autocmd("lsp_document_highlight", bufnr, {
      {
        events = { "CursorHold", "CursorHoldI" },
        desc = "highlight references when cursor holds",
        callback = function()
          if not utils.has_capability("textDocument/documentHighlight", { bufnr = bufnr }) then
            utils.del_buffer_autocmd("lsp_document_highlight", bufnr)
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
    if vim.b[bufnr].inlay_hints_enabled == nil then vim.b[bufnr].inlay_hints_enabled = vim.g.inlay_hints_enabled end
    -- TODO: remove check after dropping support for Neovim v0.9
    if vim.lsp.inlay_hint and vim.b[bufnr].inlay_hints_enabled then vim.lsp.inlay_hint(bufnr, true) end
  end

  if client.supports_method and vim.lsp.semantic_tokens then
    if vim.b[bufnr].semantic_tokens_enabled == nil then
      vim.b[bufnr].semantic_tokens_enabled = vim.g.semantic_tokens_enabled
    end
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
        map_opts = vim.tbl_deep_extend("force", map_opts, { buffer = bufnr })
        map_opts[1], map_opts.cond = nil, nil
        vim.keymap.set(mode, lhs, rhs, map_opts)
      end
    end
  end

  for id, _ in pairs(M.lsp_progress) do -- clear lingering progress messages
    if not next((vim.lsp.get_clients or vim.lsp.get_active_clients) { id = tonumber(id:match "^%d+") }) then
      M.lsp_progress[id] = nil
    end
  end

  if type(M.options.on_attach) == "function" then M.options.on_attach(client, bufnr) end
end

--- Get the server configuration for a given language server to be provided to the server's `setup()` call
---@param server_name string The name of the server
---@return table # The table of LSP options used when setting up the given language server
function M.config(server_name)
  if server_name == "lua_ls" then pcall(require, "neodev") end
  local server = require("lspconfig")[server_name]
  local opts = vim.tbl_deep_extend(
    "force",
    vim.tbl_deep_extend("force", server.document_config.default_config, server),
    { capabilities = M.capabilities, flags = M.flags }
  )
  -- HACK: add astronvim interoperability, remove after AstroNvim v4
  if type(astronvim) == "table" and type(astronvim.user_opts) == "function" then
    opts = astronvim.user_opts("lsp.config." .. server_name, opts)
  end
  if M.options.config[server_name] then
    opts = assert(vim.tbl_deep_extend("force", opts, M.options.config[server_name]))
  end
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

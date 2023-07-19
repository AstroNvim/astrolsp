local M = {}

--- Emit user event that starts with AstroLSP
---@param event string The event name to be appended to Astro
function M.event(event)
  vim.schedule(function() vim.api.nvim_exec_autocmds("User", { pattern = "AstroLsp" .. event, modeline = false }) end)
end

function M.del_buffer_autocmd(augroup, bufnr)
  local cmds_found, cmds = pcall(vim.api.nvim_get_autocmds, { group = augroup, buffer = bufnr })
  if cmds_found then vim.tbl_map(function(cmd) vim.api.nvim_del_autocmd(cmd.id) end, cmds) end
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
  for _, client in ipairs((vim.lsp.get_clients or vim.lsp.get_active_clients)(filter)) do
    if client.supports_method(capability) then return true end
  end
  return false
end

--- Toggle auto format
function M.toggle_autoformat()
  vim.g.autoformat_enabled = not vim.g.autoformat_enabled
  vim.notify(string.format("Global autoformatting %s", vim.g.autoformat_enabled and "on" or "off"))
end

--- Toggle buffer local auto format
---@param bufnr? number The buffer to toggle the autoformatting of, default the current buffer
function M.toggle_buffer_autoformat(bufnr)
  bufnr = bufnr or 0
  local old_val = vim.b[bufnr].autoformat_enabled
  if old_val == nil then old_val = vim.g.autoformat_enabled end
  vim.b[bufnr].autoformat_enabled = not old_val
  vim.notify(string.format("Buffer autoformatting %s", vim.b[bufnr].autoformat_enabled and "on" or "off"))
end

return M

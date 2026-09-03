---AstroNvim LSP Utilities
---
---Helpers for handling values decoded from LSP JSON messages.
---
---@class astrolsp.utils
local M = {}

--- LSP JSON payloads are acyclic, so avoid a traversal cache during normalization.
---@param value any value received from an LSP client
---@return any normalized value with vim.NIL converted to Lua nil
function M.normalize(value)
  if value == vim.NIL then return nil end
  if type(value) ~= "table" then return value end

  local copy
  for key, child in pairs(value) do
    local normalized_child = M.normalize(child)
    if normalized_child ~= child then
      if not copy then
        copy = setmetatable({}, getmetatable(value))
        for copy_key, copy_value in pairs(value) do
          rawset(copy, copy_key, copy_value)
        end
      end
      rawset(copy, key, normalized_child)
    end
  end
  return copy or value
end

return M

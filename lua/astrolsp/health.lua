-- ### AstroLSP Health Checks
--
-- use with `:checkhealth astrolsp`
--
-- copyright 2024
-- license GNU General Public License v3.0

local M = {}

local astrolsp = require "astrolsp"
local health = vim.health

local function check_mapping_conflicts(all_maps)
  local set_mappings, any_duplicates = {}, false
  for mode, mappings in pairs(all_maps) do
    for lhs, rhs in pairs(mappings) do
      if rhs then
        if not set_mappings[mode] then set_mappings[mode] = {} end
        local normalized_lhs = vim.api.nvim_replace_termcodes(lhs, true, true, true)
        if set_mappings[mode][normalized_lhs] then
          set_mappings[mode][normalized_lhs][lhs] = rhs
          set_mappings[mode][normalized_lhs][1] = true
          any_duplicates = true
        else
          set_mappings[mode][normalized_lhs] = { [1] = false, [lhs] = rhs }
        end
      end
    end
  end

  if any_duplicates then
    local msg = ""
    for mode, mappings in pairs(set_mappings) do
      local mode_msg
      for _, duplicate_mappings in pairs(mappings) do
        if duplicate_mappings[1] then
          if not mode_msg then
            mode_msg = ("Conflicting mappings detected in mode `%s`:\n"):format(mode)
          else
            mode_msg = mode_msg .. "\n"
          end
          for lhs, rhs in pairs(duplicate_mappings) do
            if type(lhs) == "string" then
              mode_msg = mode_msg .. ("- %s: %s\n"):format(lhs, type(rhs) == "table" and (rhs.desc or rhs[1]) or rhs)
            end
          end
        end
      end
      if mode_msg then msg = msg .. mode_msg end
    end
    health.warn(
      msg,
      "Make sure to normalize the left hand side of mappings to what is used in :h keycodes. This includes making sure to capitalize <Leader> and <LocalLeader>."
    )
  else
    health.ok "No conflicting mappings detected"
  end
end

function M.check()
  health.start "Checking for conflicting mappings"
  check_mapping_conflicts(astrolsp.config.mappings)
end

return M

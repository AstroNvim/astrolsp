local M = {}

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
end

return M

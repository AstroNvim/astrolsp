#!/usr/bin/env -S nvim -l

local tests_dir = vim.fs.dirname(debug.getinfo(1, "S").source:sub(2))
package.path = tests_dir .. "/?.lua;" .. package.path

local config = require "config"

vim.env.LAZY_OFFLINE = "1"
config.assert_ready_environment()

package.path = config.lua_root .. "/?.lua;" .. config.lua_root .. "/?/init.lua;" .. package.path
vim.opt.rtp:prepend(config.root)
vim.env.LAZY = config.lazy_path
vim.opt.rtp:prepend(config.lazy_path)
vim.opt.rtp:prepend(config.plugin_root .. "/mini.nvim")

local files = {}
for _, argument in ipairs(_G.arg) do
  if argument ~= "--minitest" then table.insert(files, argument) end
end

local MiniTest = require "mini.test"
MiniTest.setup {
  collect = {
    find_files = function()
      if #files > 0 then return files end
      return vim.fn.globpath("tests", "**/*_spec.lua", true, true)
    end,
  },
}
_G.assert = require "luassert"
MiniTest.run()

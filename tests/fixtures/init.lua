local function required(name)
  local value = vim.env[name]
  if not value or value == "" then error("Missing " .. name, 0) end
  return value
end

local root = vim.fs.normalize(required "ASTROLSP_TEST_ROOT")
local lazy_path = required "ASTROLSP_TEST_LAZY_PATH"
local plugin_root = required "ASTROLSP_TEST_PLUGIN_ROOT"
local lockfile = required "ASTROLSP_TEST_LOCKFILE"
local lua_root = required "ASTROLSP_TEST_LUA_ROOT"

vim.env.LAZY_OFFLINE = "1"
package.path = lua_root
  .. "/?.lua;"
  .. lua_root
  .. "/?/init.lua;"
  .. root
  .. "/lua/?.lua;"
  .. root
  .. "/lua/?/init.lua;"
  .. package.path
vim.opt.rtp:prepend(root)
vim.env.LAZY = lazy_path
vim.opt.rtp:prepend(lazy_path)
vim.opt.rtp:prepend(plugin_root .. "/mini.nvim")

assert(vim.fn.isdirectory(plugin_root) == 1, "Missing prepared Lazy plugin root")
assert(vim.fn.filereadable(lockfile) == 1, "Missing prepared Lazy lockfile")

local expected_init = vim.fs.normalize(root .. "/lua/astrolsp/init.lua")
local runtime_files = vim.api.nvim_get_runtime_file("lua/astrolsp/init.lua", false)
local resolved_init = runtime_files[1] and vim.fs.normalize(runtime_files[1])
assert(
  resolved_init == expected_init,
  "AstroLSP runtime path does not resolve from ASTROLSP_TEST_ROOT: " .. tostring(resolved_init)
)

vim.g.astrolsp_test_ready = true

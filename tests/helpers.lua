local MiniTest = require "mini.test"
local config = require "config"

local M = {}
local children = setmetatable({}, { __mode = "k" })
local xdg_names = { "XDG_CONFIG_HOME", "XDG_DATA_HOME", "XDG_STATE_HOME", "XDG_CACHE_HOME", "XDG_RUNTIME_DIR" }
local environment_values = {
  XDG_CONFIG_HOME = function(root) return root .. "/config" end,
  XDG_DATA_HOME = function(root) return root .. "/data" end,
  XDG_STATE_HOME = function(root) return root .. "/state" end,
  XDG_CACHE_HOME = function(root) return root .. "/cache" end,
  XDG_RUNTIME_DIR = function(root) return root .. "/runtime" end,
  ASTROLSP_TEST_ROOT = function() return config.root end,
  ASTROLSP_TEST_LAZY_PATH = function() return config.lazy_path end,
  ASTROLSP_TEST_PLUGIN_ROOT = function() return config.plugin_root end,
  ASTROLSP_TEST_LOCKFILE = function() return config.lockfile end,
  ASTROLSP_TEST_LUA_ROOT = function() return config.lua_root end,
  LC_ALL = function() return "C" end,
  LANG = function() return "C" end,
  TZ = function() return "UTC" end,
}
local unset_environment = {}

local function make_case()
  local root = vim.fn.tempname()
  assert(vim.fn.mkdir(root, "p") == 1 or vim.fn.isdirectory(root) == 1)
  for _, path in ipairs { "config", "data", "state", "cache", "runtime" } do
    assert(vim.fn.mkdir(root .. "/" .. path, "p") == 1 or vim.fn.isdirectory(root .. "/" .. path) == 1)
  end
  return root
end

local function with_environment(root, callback)
  local previous = {}
  for name, value in pairs(environment_values) do
    previous[name] = vim.uv.os_getenv(name) or unset_environment
    vim.env[name] = value(root)
  end
  local ok, result = xpcall(callback, debug.traceback)
  for name, value in pairs(previous) do
    if value == unset_environment then
      vim.env[name] = nil
    else
      vim.env[name] = value
    end
  end
  if not ok then error(result, 0) end
  return result
end

local function append_error(errors, prefix, callback)
  local ok, result = xpcall(callback, debug.traceback)
  if not ok then table.insert(errors, prefix .. tostring(result)) end
  return ok, result
end

local function cleanup_child(child, root)
  local errors = {}
  if child then
    local running_ok, running = append_error(
      errors,
      "Cannot inspect child Neovim process: ",
      function() return child:is_running() end
    )
    if running_ok and running then
      append_error(errors, "Cannot stop child Neovim process: ", function() child:stop() end)
    end
  end
  if root then
    append_error(errors, "Failed to remove child fixture root: ", function()
      if vim.fn.delete(root, "rf") ~= 0 then error(root, 0) end
    end)
  end
  return errors
end

function M.start_child(options)
  options = options or {}
  local root, child
  local ok, result = xpcall(function()
    root = make_case()
    child = MiniTest.new_child_neovim()
    with_environment(
      root,
      function() child.start { "-u", config.root .. "/tests/fixtures/init.lua", "--cmd", "set loadplugins" } end
    )
    M.wait_until(
      child,
      options.ready_expression or "vim.g.astrolsp_test_ready == true",
      "child bootstrap",
      options.timeout
    )
  end, debug.traceback)
  if not ok then
    local cleanup_errors = cleanup_child(child, root)
    if #cleanup_errors > 0 then result = result .. "\n" .. table.concat(cleanup_errors, "\n") end
    error(result, 0)
  end
  children[child] = root
  return child
end

function M.wait_until(child, expression, description, timeout)
  timeout = timeout or 10000
  local ready = vim.wait(timeout, function()
    local ok, value = pcall(child.lua_get, expression)
    return ok and value == true
  end, 20)
  assert(ready, ("Timed out waiting for %s after %d ms"):format(description, timeout))
end

function M.stop_child(child)
  if not child then return end
  local root = children[child]
  children[child] = nil
  local errors = cleanup_child(child, root)
  if #errors > 0 then error(table.concat(errors, "\n"), 0) end
  return root
end

function M.parent_xdg_environment()
  local snapshot = {}
  for _, name in ipairs(xdg_names) do
    snapshot[name] = vim.uv.os_getenv(name)
  end
  return snapshot
end

return M

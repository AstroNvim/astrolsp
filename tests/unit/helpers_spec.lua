local MiniTest = require "mini.test"
local config = require "config"
local helpers = require "helpers"

local T = MiniTest.new_set()
local environment_names = {
  "XDG_CONFIG_HOME",
  "XDG_DATA_HOME",
  "XDG_STATE_HOME",
  "XDG_CACHE_HOME",
  "XDG_RUNTIME_DIR",
  "ASTROLSP_TEST_ROOT",
  "ASTROLSP_TEST_LAZY_PATH",
  "ASTROLSP_TEST_PLUGIN_ROOT",
  "ASTROLSP_TEST_LOCKFILE",
  "ASTROLSP_TEST_LUA_ROOT",
  "LC_ALL",
  "LANG",
  "TZ",
}
local unset_environment = {}

local function snapshot_environment()
  local snapshot = {}
  for _, name in ipairs(environment_names) do
    snapshot[name] = vim.uv.os_getenv(name)
  end
  return snapshot
end

local function set_environment(values)
  for _, name in ipairs(environment_names) do
    if values[name] == unset_environment then
      vim.env[name] = nil
    else
      vim.env[name] = values[name]
    end
  end
end

local function with_environment(values, callback)
  local previous = snapshot_environment()
  local ok, result = xpcall(function()
    set_environment(values)
    return callback()
  end, debug.traceback)
  set_environment(previous)
  if not ok then error(result, 0) end
  return result
end

local function with_restored_child_factory(callback)
  local original_factory = MiniTest.new_child_neovim
  local ok, result = xpcall(callback, debug.traceback)
  MiniTest.new_child_neovim = original_factory
  if not ok then error(result, 0) end
  return result
end

local function helper_test(callback)
  return function() return with_restored_child_factory(callback) end
end

local function initial_environment(value)
  local values = {}
  for _, name in ipairs(environment_names) do
    values[name] = value == nil and unset_environment or value .. name
  end
  return values
end

local function child_environment(root)
  return {
    XDG_CONFIG_HOME = root .. "/config",
    XDG_DATA_HOME = root .. "/data",
    XDG_STATE_HOME = root .. "/state",
    XDG_CACHE_HOME = root .. "/cache",
    XDG_RUNTIME_DIR = root .. "/runtime",
    ASTROLSP_TEST_ROOT = config.root,
    ASTROLSP_TEST_LAZY_PATH = config.lazy_path,
    ASTROLSP_TEST_PLUGIN_ROOT = config.plugin_root,
    ASTROLSP_TEST_LOCKFILE = config.lockfile,
    ASTROLSP_TEST_LUA_ROOT = config.lua_root,
    LC_ALL = "C",
    LANG = "C",
    TZ = "UTC",
  }
end

local function assert_child_environment(root) assert.same(child_environment(root), snapshot_environment()) end

local initial_environments = { initial_environment "parent-", initial_environment() }

T["HARNESS-CHILD-001 snapshots parent XDG state without mutation"] = helper_test(function()
  local snapshot = helpers.parent_xdg_environment()
  assert.is_table(snapshot)
  for _, name in ipairs { "XDG_CONFIG_HOME", "XDG_DATA_HOME", "XDG_STATE_HOME", "XDG_CACHE_HOME", "XDG_RUNTIME_DIR" } do
    assert.equals(vim.uv.os_getenv(name), snapshot[name])
  end
end)

T["HARNESS-CHILD-001 restores all managed parent state after successful starts"] = helper_test(function()
  MiniTest.new_child_neovim = function()
    return {
      start = function()
        local root = vim.fs.dirname(vim.env.XDG_CONFIG_HOME)
        for _, path in ipairs {
          root,
          root .. "/config",
          root .. "/data",
          root .. "/state",
          root .. "/cache",
          root .. "/runtime",
        } do
          assert.equals(1, vim.fn.isdirectory(path))
        end
        assert_child_environment(root)
      end,
      lua_get = function() return true end,
      is_running = function() return false end,
    }
  end

  for _, initial in ipairs(initial_environments) do
    with_environment(initial, function()
      local before = snapshot_environment()
      local child = helpers.start_child()
      local after = snapshot_environment()
      local root = helpers.stop_child(child)
      assert.same(before, after)
      assert.is_nil(vim.uv.fs_lstat(root))
    end)
  end
end)

T["HARNESS-CHILD-001 restores all managed parent state and cleans failed starts"] = helper_test(function()
  local before = helpers.parent_xdg_environment()

  for _, initial in ipairs(initial_environments) do
    with_environment(initial, function()
      local initial_snapshot = snapshot_environment()
      local root
      MiniTest.new_child_neovim = function()
        return {
          start = function()
            root = vim.fs.dirname(vim.env.XDG_CONFIG_HOME)
            assert_child_environment(root)
            error("child start failure", 0)
          end,
          is_running = function() return false end,
        }
      end
      local ok, message = pcall(helpers.start_child)
      assert.is_false(ok)
      assert.matches("child start failure", message)
      assert.same(initial_snapshot, snapshot_environment())
      assert.is_nil(vim.uv.fs_lstat(root))
    end)
  end
  assert.same(before, helpers.parent_xdg_environment())
end)

T["HARNESS-CHILD-001 reports the bounded readiness timeout"] = helper_test(function()
  local ok, message =
    pcall(helpers.wait_until, { lua_get = function() return false end }, "false", "fixture readiness", 5)
  assert.is_false(ok)
  assert.matches("Timed out waiting for fixture readiness after 5 ms", message, 1, true)
end)

T["HARNESS-CHILD-001 removes a fixture root when stopping the child fails"] = helper_test(function()
  local root
  MiniTest.new_child_neovim = function()
    return {
      start = function() root = vim.fs.dirname(vim.env.XDG_CONFIG_HOME) end,
      lua_get = function() return true end,
      is_running = function() return true end,
      stop = function() error("child stop failure", 0) end,
    }
  end

  local child = helpers.start_child()
  local ok, message = pcall(helpers.stop_child, child)
  assert.is_false(ok)
  assert.matches("child stop failure", message)
  assert.is_nil(vim.uv.fs_lstat(root))
end)

T["HARNESS-CHILD-001 aggregates start and cleanup errors"] = helper_test(function()
  MiniTest.new_child_neovim = function()
    return {
      start = function() error("child start failure", 0) end,
      is_running = function() error("child inspection failure", 0) end,
    }
  end

  local ok, message = pcall(helpers.start_child)
  assert.is_false(ok)
  assert.matches("child start failure", message)
  assert.matches("Cannot inspect child Neovim process", message)
  assert.matches("child inspection failure", message)
end)

return T

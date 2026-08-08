local MiniTest = require "mini.test"
local helpers = require "unit_helpers"

local T = MiniTest.new_set()

local function with_restored_packages(names, callback)
  local entries = {}
  for _, name in ipairs(names) do
    entries[name] = { loaded = package.loaded[name], preload = package.preload[name] }
  end
  local ok, result = xpcall(callback, debug.traceback)
  for name, entry in pairs(entries) do
    package.loaded[name] = entry.loaded
    package.preload[name] = entry.preload
  end
  if not ok then error(result, 0) end
  return result
end

local function with_notify(notify, callback)
  local original_notify = vim.notify
  vim.notify = notify
  local ok, result = xpcall(callback, debug.traceback)
  vim.notify = original_notify
  if not ok then error(result, 0) end
  return result
end

local function with_restored_vim_callbacks(callback)
  local original_schedule = vim.schedule
  local original_defer_fn = vim.defer_fn
  local ok, result = xpcall(function() return callback(original_schedule, original_defer_fn) end, debug.traceback)
  vim.schedule = original_schedule
  vim.defer_fn = original_defer_fn
  if not ok then error(result, 0) end
  return result
end

T["HARNESS-MODULE-001 restores package entries and nested Vim replacements"] = function()
  local module_name = "astrolsp_test_module"
  local dependency_name = "astrolsp_test_dependency"
  local handler_name = "astrolsp/test"
  local original_module = { original = true }
  local original_dependency = { original = true }
  local original_preload = function() return { original = true } end
  local original_handler = vim.lsp.handlers[handler_name]
  with_restored_vim_callbacks(function(original_schedule, original_defer_fn)
    with_restored_packages({ module_name, dependency_name }, function()
      package.loaded[module_name] = original_module
      package.preload[module_name] = function() return { loaded = true } end
      package.loaded[dependency_name] = original_dependency
      package.preload[dependency_name] = original_preload

      helpers.with_module(module_name, {
        loaded = { [dependency_name] = { temporary = true } },
        preload = { [dependency_name] = function() return { temporary = true } end },
        vim = { lsp = { handlers = { [handler_name] = function() return "temporary" end } } },
      }, function(module)
        assert.is_true(module.loaded)
        assert.same({ temporary = true }, package.loaded[dependency_name])
        assert.is_function(package.preload[dependency_name])
        assert.equals("temporary", vim.lsp.handlers[handler_name]())
      end)

      assert.equals(original_module, package.loaded[module_name])
      assert.equals(original_dependency, package.loaded[dependency_name])
      assert.equals(original_preload, package.preload[dependency_name])
      assert.equals(original_handler, vim.lsp.handlers[handler_name])
      assert.equals(original_schedule, vim.schedule)
      assert.equals(original_defer_fn, vim.defer_fn)
    end)
  end)
end

T["HARNESS-MODULE-001 isolates notifications and drains scheduled work in order"] = function()
  local module_name = "astrolsp_test_callbacks"
  local notifications, events = 0, {}
  local isolated_notify = function() notifications = notifications + 1 end
  with_restored_packages({ module_name }, function()
    with_notify(isolated_notify, function()
      package.preload[module_name] = function() return {} end

      helpers.with_module(module_name, nil, function(_, context)
        vim.notify "isolated"
        vim.schedule(function()
          table.insert(events, "scheduled")
          vim.defer_fn(function() table.insert(events, "deferred-from-scheduled") end, 1)
        end)
        vim.defer_fn(function()
          table.insert(events, "deferred")
          vim.schedule(function() table.insert(events, "scheduled-from-deferred") end)
        end, 1)
        assert.equals(1, context.scheduled_count())
        assert.equals(1, context.deferred_count())
      end)

      assert.equals(0, notifications)
      assert.same({ "scheduled", "deferred", "deferred-from-scheduled", "scheduled-from-deferred" }, events)
      assert.equals(0, notifications)
      assert.equals(isolated_notify, vim.notify)
    end)
  end)
end

T["HARNESS-MODULE-001 preserves callback errors and drains every queued callback"] = function()
  local module_name = "astrolsp_test_callback_failure"
  local completed = false
  local original_module = { original = true }
  local original_preload = function() return { original = true } end
  with_restored_vim_callbacks(function(original_schedule, original_defer_fn)
    with_restored_packages({ module_name }, function()
      package.loaded[module_name] = original_module
      package.preload[module_name] = original_preload

      local ok, message = pcall(helpers.with_module, module_name, nil, function()
        vim.schedule(function() error("scheduled cleanup failure", 0) end)
        vim.defer_fn(function() completed = true end, 1)
        error("callback failure", 0)
      end)

      assert.is_false(ok)
      assert.matches("callback failure", message)
      assert.matches("scheduled cleanup failure", message)
      assert.is_true(completed)
      assert.equals(original_module, package.loaded[module_name])
      assert.equals(original_preload, package.preload[module_name])
      assert.equals(original_schedule, vim.schedule)
      assert.equals(original_defer_fn, vim.defer_fn)
    end)
  end)
end

return T

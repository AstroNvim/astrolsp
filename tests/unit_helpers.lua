local M = {}

M.remove = {}

local function restore_entries(entries)
  for name, entry in pairs(entries) do
    package.loaded[name] = entry.loaded
    package.preload[name] = entry.preload
  end
end

function M.with_module(module_name, opts, callback)
  opts = opts or {}
  callback = assert(callback, "A module callback is required")
  local names = { [module_name] = true }
  for name in pairs(opts.loaded or {}) do
    names[name] = true
  end
  for name in pairs(opts.preload or {}) do
    names[name] = true
  end

  local packages = {}
  for name in pairs(names) do
    packages[name] = { loaded = package.loaded[name], preload = package.preload[name] }
  end

  local replacements = {}
  local function replace(target, values)
    for name, value in pairs(values or {}) do
      if target == vim and name ~= "g" and type(value) == "table" and type(target[name]) == "table" then
        replace(target[name], value)
      else
        table.insert(replacements, { target = target, name = name, value = target[name] })
        target[name] = value
      end
    end
  end

  local original_notify = vim.notify
  local scheduled = {}
  local deferred = {}
  local function drain_callbacks()
    local errors = {}
    local function drain(queue)
      for _, callback_fn in ipairs(queue) do
        local callback_ok, callback_error = xpcall(callback_fn, debug.traceback)
        if not callback_ok then table.insert(errors, callback_error) end
      end
    end
    while #scheduled > 0 or #deferred > 0 do
      local scheduled_callbacks = scheduled
      scheduled = {}
      drain(scheduled_callbacks)
      local deferred_callbacks = deferred
      deferred = {}
      drain(deferred_callbacks)
    end
    if #errors > 0 then error(table.concat(errors, "\n"), 0) end
  end
  local context = {
    drain = drain_callbacks,
    scheduled_count = function() return #scheduled end,
    deferred_count = function() return #deferred end,
  }

  local ok, result = xpcall(function()
    for name, value in pairs(opts.loaded or {}) do
      if value == M.remove then
        package.loaded[name] = nil
      else
        package.loaded[name] = value
      end
    end
    for name, value in pairs(opts.preload or {}) do
      if value == M.remove then
        package.preload[name] = nil
      else
        package.preload[name] = value
      end
    end
    package.loaded[module_name] = nil
    replace(vim, opts.vim)
    vim.notify = opts.notify or function() end
    local original_schedule, original_defer = vim.schedule, vim.defer_fn
    vim.schedule = function(callback_fn) table.insert(scheduled, callback_fn) end
    vim.defer_fn = function(callback_fn) table.insert(deferred, callback_fn) end
    table.insert(replacements, { target = vim, name = "schedule", value = original_schedule })
    table.insert(replacements, { target = vim, name = "defer_fn", value = original_defer })
    return callback(require(module_name), context)
  end, debug.traceback)

  local cleanup_errors = {}
  local function cleanup(callback_fn)
    local cleanup_ok, cleanup_error = xpcall(callback_fn, debug.traceback)
    if not cleanup_ok then table.insert(cleanup_errors, cleanup_error) end
  end
  cleanup(drain_callbacks)
  cleanup(function() vim.notify = original_notify end)
  cleanup(function()
    for index = #replacements, 1, -1 do
      local replacement = replacements[index]
      replacement.target[replacement.name] = replacement.value
    end
  end)
  cleanup(function() restore_entries(packages) end)
  if not ok then
    if #cleanup_errors > 0 then result = result .. "\nCleanup failed: " .. table.concat(cleanup_errors, "\n") end
    error(result, 0)
  end
  if #cleanup_errors > 0 then error(table.concat(cleanup_errors, "\n"), 0) end
  return result
end

return M

local M = {}

local handler_states = setmetatable({}, { __mode = "k" })
local method_states = setmetatable({}, { __mode = "k" })

local function wrap(states, target, name, callback)
  local target_states = states[target]
  if not target_states then
    target_states = {}
    states[target] = target_states
  end

  local state = target_states[name]
  if not state then
    state = { original = target[name] }
    state.wrapper = function(...) return state.callback(state.original, ...) end
    target_states[name] = state
  elseif target[name] ~= state.wrapper then
    state.original = target[name]
  end

  state.callback = callback
  target[name] = state.wrapper
end

function M.wrap_handler(handlers, method, callback) wrap(handler_states, handlers, method, callback) end

function M.wrap_method(methods, method, callback) wrap(method_states, methods, method, callback) end

function M.restore_inactive_methods(methods, active_methods)
  local target_states = method_states[methods]
  if not target_states then return end

  for method, state in pairs(target_states) do
    if not active_methods[method] then
      if methods[method] == state.wrapper then methods[method] = state.original end
      target_states[method] = nil
    end
  end

  if not next(target_states) then method_states[methods] = nil end
end

return M

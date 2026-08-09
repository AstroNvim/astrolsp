local MiniTest = require "mini.test"
local helpers = require "helpers"

local child
local T = MiniTest.new_set {
  hooks = {
    pre_case = function() child = nil end,
    post_case = function()
      helpers.stop_child(child)
      child = nil
    end,
  },
}

T["INIT-COND-001 creates a capability-gated command for an attached fake client"] = function()
  child = helpers.start_child()
  local state = child.lua_get [[(function()
    local astrolsp = require "astrolsp"
    local buffer = vim.api.nvim_get_current_buf()
    local calls = 0
    local client = {
      id = 901,
      name = "semantic-client",
      supports_method = function(_, method, requested_buffer)
        return method == "textDocument/formatting" and requested_buffer == buffer
      end,
    }
    astrolsp.setup {
      commands = {
        AstroLspSemanticFormat = {
          function() calls = calls + 1 end,
          cond = "textDocument/formatting",
        },
      },
    }
    vim.lsp.get_client_by_id = function(id) return id == client.id and client or nil end
    vim.lsp.get_clients = function(options)
      if options and options.bufnr and options.bufnr ~= buffer then return {} end
      return { client }
    end
    vim.api.nvim_exec_autocmds("LspAttach", { buffer = buffer, data = { client_id = client.id } })
    vim.cmd "AstroLspSemanticFormat"
    return { calls = calls, exists = vim.fn.exists(":AstroLspSemanticFormat") == 2 }
  end)()]]
  assert.is_true(state.exists)
  assert.equals(1, state.calls)
end

T["INIT-COND-001 applies every condition variant to autocmd callbacks"] = function()
  child = helpers.start_child()
  local calls = child.lua_get [[(function()
    local astrolsp = require "astrolsp"
    local buffer = vim.api.nvim_get_current_buf()
    local calls = {}
    local client = {
      id = 907,
      name = "conditions",
      supports_method = function(_, method, requested_buffer)
        return method == "textDocument/formatting" and requested_buffer == buffer
      end,
    }
    local function autocmd(name)
      return {
        { event = "BufEnter", callback = function() table.insert(calls, name) end },
      }
    end
    astrolsp.setup {
      autocmds = {
        astrolsp_cond_method = vim.tbl_extend("force", autocmd "method", { cond = "textDocument/formatting" }),
        astrolsp_cond_boolean = vim.tbl_extend("force", autocmd "boolean", { cond = true }),
        astrolsp_cond_function = vim.tbl_extend("force", autocmd "function", {
          cond = function(attached, bufnr) return attached == client and bufnr == buffer end,
        }),
        astrolsp_cond_nil = autocmd "nil",
        astrolsp_cond_disabled = vim.tbl_extend("force", autocmd "disabled", { cond = false }),
      },
    }
    vim.lsp.get_client_by_id = function(id) return id == client.id and client or nil end
    vim.lsp.get_clients = function(options)
      if options and options.bufnr and options.bufnr ~= buffer then return {} end
      return { client }
    end
    vim.api.nvim_exec_autocmds("LspAttach", { buffer = buffer, data = { client_id = client.id } })
    vim.api.nvim_exec_autocmds("BufEnter", { buffer = buffer })
    return calls
  end)()]]
  local received = {}
  for _, name in ipairs(calls) do
    received[name] = true
  end
  assert.same({ method = true, boolean = true, ["function"] = true, ["nil"] = true }, received)
end

T["INIT-BUFFER-002 resolves the current matching client when an autocmd executes"] = function()
  child = helpers.start_child()
  local state = child.lua_get [[(function()
    local astrolsp = require "astrolsp"
    local buffer = vim.api.nvim_get_current_buf()
    local calls = {}
    local first = {
      id = 902,
      name = "first",
      supports_method = function(_, method) return method == "textDocument/formatting" end,
    }
    local current = first
    astrolsp.setup {
      autocmds = {
        astrolsp_semantic_autocmd = {
          cond = "textDocument/formatting",
          {
            event = "BufEnter",
            callback = function(args, client, bufnr) table.insert(calls, { args.event, client.name, bufnr }) end,
          },
        },
      },
    }
    vim.lsp.get_client_by_id = function(id) return id == first.id and first or nil end
    vim.lsp.get_clients = function(options)
      if options and options.bufnr and options.bufnr ~= buffer then return {} end
      return { current }
    end
    vim.api.nvim_exec_autocmds("LspAttach", { buffer = buffer, data = { client_id = first.id } })
    current = {
      id = 903,
      name = "replacement",
      supports_method = function(_, method) return method == "textDocument/formatting" end,
    }
    vim.api.nvim_exec_autocmds("BufEnter", { buffer = buffer })
    current = { id = 904, name = "unsupported", supports_method = function() return false end }
    vim.api.nvim_exec_autocmds("BufEnter", { buffer = buffer })
    return { buffer = buffer, calls = calls }
  end)()]]
  assert.same({ { "BufEnter", "replacement", state.buffer } }, state.calls)
end

T["INIT-BUFFER-002 preserves autocmd specs after creation errors"] = function()
  child = helpers.start_child()
  local state = child.lua_get [[(function()
    local astrolsp = require "astrolsp"
    local buffer = vim.api.nvim_get_current_buf()
    local callback = function() end
    local spec = { event = "BufEnter", pattern = "*.lua", callback = callback, desc = "Broken autocmd" }
    local original = vim.deepcopy(spec)
    local client = {
      id = 908,
      name = "broken-autocmd",
      supports_method = function(_, method) return method == "textDocument/formatting" end,
    }
    astrolsp.setup {
      autocmds = {
        astrolsp_broken_autocmd = { cond = "textDocument/formatting", spec },
      },
    }
    vim.lsp.get_clients = function() return { client } end
    local original_create = vim.api.nvim_create_autocmd
    vim.api.nvim_create_autocmd = function(event)
      if event == "BufEnter" then error "autocmd API failure" end
      return original_create(event)
    end
    local ok, message = pcall(astrolsp.on_attach, client, buffer)
    vim.api.nvim_create_autocmd = original_create
    return {
      ok = ok,
      message = message,
      unchanged = vim.deep_equal(spec, original),
      callback_is_original = rawequal(spec.callback, callback),
    }
  end)()]]
  assert.is_false(state.ok)
  assert.matches("autocmd API failure", state.message)
  assert.is_true(state.unchanged)
  assert.is_true(state.callback_is_original)
end

T["INIT-DETACH-001 retains multi-buffer state then clears final client progress"] = function()
  child = helpers.start_child()
  local state = child.lua_get [[(function()
    local astrolsp = require "astrolsp"
    local first = vim.api.nvim_get_current_buf()
    local second = vim.api.nvim_create_buf(true, true)
    local events = 0
    local client = { id = 905, name = "detach", attached_buffers = { [first] = true, [second] = true } }
    vim.lsp.get_client_by_id = function(id) return id == client.id and client or nil end
    vim.api.nvim_create_autocmd("User", {
      pattern = "AstroLspProgress",
      callback = function() events = events + 1 end,
    })
    astrolsp.setup {}
    astrolsp.attached_clients[client.id] = client
    astrolsp.lsp_progress["905.string.work"] = { kind = "report" }
    local first_present_during_detach = client.attached_buffers[first] == true
    vim.api.nvim_exec_autocmds("LspDetach", { buffer = first, data = { client_id = client.id } })
    local retained = astrolsp.attached_clients[client.id] ~= nil and astrolsp.lsp_progress["905.string.work"] ~= nil
    client.attached_buffers[first] = nil
    local second_present_during_detach = client.attached_buffers[second] == true
    vim.api.nvim_exec_autocmds("LspDetach", { buffer = second, data = { client_id = client.id } })
    return {
      first = first,
      second = second,
      first_present_during_detach = first_present_during_detach,
      second_present_during_detach = second_present_during_detach,
      retained = retained,
      client = astrolsp.attached_clients[client.id],
      progress = astrolsp.lsp_progress["905.string.work"],
      events = events,
    }
  end)()]]
  assert.is_true(state.first_present_during_detach)
  assert.is_true(state.second_present_during_detach)
  assert.is_true(state.first ~= state.second)
  assert.is_true(state.retained)
  assert.is_nil(state.client)
  assert.is_nil(state.progress)
  assert.equals(1, state.events)
end

T["INIT-DETACH-001 clears state for an unavailable client ID"] = function()
  child = helpers.start_child()
  local state = child.lua_get [[(function()
    local astrolsp = require "astrolsp"
    local events = 0
    vim.lsp.get_client_by_id = function() return nil end
    vim.api.nvim_create_autocmd("User", {
      pattern = "AstroLspProgress",
      callback = function() events = events + 1 end,
    })
    astrolsp.setup {}
    astrolsp.attached_clients[909] = { id = 909 }
    astrolsp.lsp_progress["909.string.work"] = { kind = "report" }
    vim.api.nvim_exec_autocmds("LspDetach", { buffer = vim.api.nvim_get_current_buf(), data = { client_id = 909 } })
    return {
      client = astrolsp.attached_clients[909],
      progress = astrolsp.lsp_progress["909.string.work"],
      events = events,
    }
  end)()]]
  assert.is_nil(state.client)
  assert.is_nil(state.progress)
  assert.equals(1, state.events)
end

T["INIT-HANDLER-001 uses fallback progress collection and exact prior-handler delegation"] = function()
  child = helpers.start_child()
  local state = child.lua_get [[(function()
    local astrolsp = require "astrolsp"
    local original_create = vim.api.nvim_create_autocmd
    local input_error = {}
    local prior_handler_error = {}
    local result = { token = "fallback", value = { kind = "begin" } }
    local context = { client_id = 906 }
    local prior_calls, prior_arguments, progress_before_prior = 0, nil, nil
    vim.api.nvim_create_autocmd = function(event, options)
      if event == "LspProgress" then error "LspProgress unavailable" end
      return original_create(event, options)
    end
    vim.lsp.handlers["$/progress"] = function(err, res, ctx)
      prior_calls = prior_calls + 1
      prior_arguments = { err = err, res = res, ctx = ctx }
      progress_before_prior = astrolsp.lsp_progress["906.string.fallback"]
      error(prior_handler_error)
    end
    astrolsp.setup {}
    vim.api.nvim_create_autocmd = original_create
    local ok, handler_error = pcall(vim.lsp.handlers["$/progress"], input_error, result, context)
    return {
      prior_calls = prior_calls,
      error_identity = not ok and rawequal(handler_error, prior_handler_error),
      err_identity = rawequal(prior_arguments.err, input_error),
      res_identity = rawequal(prior_arguments.res, result),
      ctx_identity = rawequal(prior_arguments.ctx, context),
      progress_before_prior = rawequal(progress_before_prior, result.value),
      progress = astrolsp.lsp_progress["906.string.fallback"],
    }
  end)()]]
  assert.equals(1, state.prior_calls)
  assert.is_true(state.error_identity)
  assert.is_true(state.err_identity)
  assert.is_true(state.res_identity)
  assert.is_true(state.ctx_identity)
  assert.is_true(state.progress_before_prior)
  assert.same({ kind = "begin" }, state.progress)
end

return T

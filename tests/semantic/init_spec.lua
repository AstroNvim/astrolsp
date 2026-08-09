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

T["HARNESS-CHILD-001 isolates all child XDG paths and preserves parent state"] = function()
  local before = helpers.parent_xdg_environment()
  child = helpers.start_child()
  local state = child.lua_get [[(function()
    local paths = {}
    for key, name in pairs {
      config = "XDG_CONFIG_HOME",
      data = "XDG_DATA_HOME",
      state = "XDG_STATE_HOME",
      cache = "XDG_CACHE_HOME",
      runtime = "XDG_RUNTIME_DIR",
    } do
      local path = vim.env[name]
      paths[key] = {
        path = path,
        root = vim.fn.fnamemodify(path, ":h"),
        exists = vim.uv.fs_stat(path) ~= nil,
      }
    end
    local root = paths.config.root
    return {
      ready = vim.g.astrolsp_test_ready == true,
      root = root,
      root_exists = vim.uv.fs_stat(root) ~= nil,
      paths = paths,
    }
  end)()]]
  assert.is_true(state.ready)
  assert.is_true(state.root_exists)
  local xdg_names = {
    config = "XDG_CONFIG_HOME",
    data = "XDG_DATA_HOME",
    state = "XDG_STATE_HOME",
    cache = "XDG_CACHE_HOME",
    runtime = "XDG_RUNTIME_DIR",
  }
  local paths = {}
  for key, environment_name in pairs(xdg_names) do
    local path = state.paths[key]
    assert.is_true(path.exists)
    assert.equals(state.root, path.root)
    assert.is_false(path.path == before[environment_name])
    assert.is_nil(paths[path.path])
    paths[path.path] = true
  end
  assert.same(before, helpers.parent_xdg_environment())
  local root = helpers.stop_child(child)
  child = nil
  assert.equals(state.root, root)
  assert.is_nil(vim.uv.fs_lstat(root))
  for _, path in pairs(state.paths) do
    assert.is_nil(vim.uv.fs_lstat(path.path))
  end
end

T["INIT-MERGE-001 preserves formatting and feature defaults"] = function()
  child = helpers.start_child()
  local state = child.lua_get [[(function()
    local astrolsp = require "astrolsp"
    astrolsp.setup {
      formatting = { format_on_save = false },
      features = { signature_help = true },
    }
    return {
      enabled = astrolsp.config.formatting.format_on_save.enabled,
      disabled = astrolsp.config.formatting.disabled,
      codelens = astrolsp.config.features.codelens,
      signature_help = astrolsp.config.features.signature_help,
    }
  end)()]]
  assert.is_false(state.enabled)
  assert.same({}, state.disabled)
  assert.is_true(state.codelens)
  assert.is_true(state.signature_help)
end

T["INIT-FORMAT-003 normalizes a disabled format-on-save value"] = function()
  child = helpers.start_child()
  local enabled = child.lua_get [[(function()
    local astrolsp = require "astrolsp"
    astrolsp.setup { formatting = { format_on_save = false } }
    return astrolsp.config.formatting.format_on_save.enabled
  end)()]]
  assert.is_false(enabled)
end

T["HARNESS-CHILD-001 reports bootstrap timeouts without mutating parent XDG state"] = function()
  local before = helpers.parent_xdg_environment()
  local started, message = pcall(helpers.start_child, { ready_expression = "false", timeout = 25 })
  assert.is_false(started)
  assert.matches("Timed out waiting for child bootstrap", message)
  assert.same(before, helpers.parent_xdg_environment())
end

T["INIT-RENAME-001 gates didRenameFiles on a successful AstroCore event"] = function()
  child = helpers.start_child()
  local state = child.lua_get [[(function()
    local calls = {}
    package.loaded["astrolsp.file_operations"] = {
      willRenameFiles = function(data) table.insert(calls, { "will", data.from }) end,
      didRenameFiles = function(data) table.insert(calls, { "did", data.to }) end,
    }
    local astrolsp = require "astrolsp"
    astrolsp.setup {}
    vim.api.nvim_exec_autocmds("User", { pattern = "AstroRenameFilePre", data = { from = "old" } })
    vim.api.nvim_exec_autocmds("User", { pattern = "AstroRenameFilePost", data = { success = false, to = "no" } })
    vim.api.nvim_exec_autocmds("User", { pattern = "AstroRenameFilePost", data = { success = true, to = "new" } })
    return calls
  end)()]]
  assert.same({ { "will", "old" }, { "did", "new" } }, state)
end

T["INIT-FEATURE-001 configures legacy CodeLens and semantic-token compatibility paths"] = function()
  child = helpers.start_child()
  local state = child.lua_get [[(function()
    local astrolsp = require "astrolsp"
    local buffer = vim.api.nvim_get_current_buf()
    local refreshes = {}
    vim.lsp.codelens.enable = nil
    vim.lsp.semantic_tokens.enable = nil
    vim.lsp.codelens.refresh = function(options) table.insert(refreshes, options.bufnr) end
    vim.g.astrolsp_test_semantic_tokens_stopped = false
    vim.lsp.semantic_tokens.stop = function(bufnr, client_id)
      vim.g.astrolsp_test_semantic_tokens_stop = { bufnr, client_id }
      vim.g.astrolsp_test_semantic_tokens_stopped = true
    end
    local client = {
      id = 501,
      name = "legacy",
      server_capabilities = { semanticTokensProvider = {} },
      supports_method = function(_, method) return method == "textDocument/codeLens" or method == "textDocument/semanticTokens/full" end,
    }
    astrolsp.config.features = { codelens = true, semantic_tokens = false }
    astrolsp.on_attach(client, buffer)
    local disabled_capability = client.server_capabilities.semanticTokensProvider == nil
    client.server_capabilities.semanticTokensProvider = {}
    astrolsp.config.features.semantic_tokens = true
    vim.b[buffer].semantic_tokens = nil
    astrolsp.on_attach(client, buffer)
    local initialized = vim.b[buffer].semantic_tokens == true
    vim.b[buffer].semantic_tokens = false
    astrolsp.on_attach(client, buffer)
    return {
      buffer = buffer,
      refreshes = refreshes,
      disabled = disabled_capability,
      initialized = initialized,
    }
  end)()]]
  helpers.wait_until(child, "vim.g.astrolsp_test_semantic_tokens_stopped == true", "legacy semantic token stop")
  state.stops = child.lua_get [[vim.g.astrolsp_test_semantic_tokens_stop]]
  assert.same({ state.buffer, state.buffer, state.buffer }, state.refreshes)
  assert.is_true(state.disabled)
  assert.is_true(state.initialized)
  assert.same({ state.buffer, 501 }, state.stops)
end

T["INIT-FEATURE-001 applies all Neovim 0.12 feature gates"] = function()
  if vim.fn.has "nvim-0.12" == 0 then return end
  child = helpers.start_child()
  local calls = child.lua_get [[(function()
    local astrolsp = require "astrolsp"
    local calls = {}
    local original_inlay_hint_enable = vim.lsp.inlay_hint.enable
    local original_semantic_tokens_enable = vim.lsp.semantic_tokens.enable
    local original_linked_editing_enable = vim.lsp.linked_editing_range.enable
    local original_codelens_enable = vim.lsp.codelens.enable
    local original_inline_completion_enable = vim.lsp.inline_completion.enable
    vim.lsp.inlay_hint.enable = function(enabled) table.insert(calls, { "inlay_hints", enabled }) end
    vim.lsp.semantic_tokens.enable = function(enabled) table.insert(calls, { "semantic_tokens", enabled }) end
    vim.lsp.linked_editing_range.enable = function(enabled) table.insert(calls, { "linked_editing_range", enabled }) end
    vim.lsp.codelens.enable = function(enabled) table.insert(calls, { "codelens", enabled }) end
    vim.lsp.inline_completion.enable = function(enabled) table.insert(calls, { "inline_completion", enabled }) end
    astrolsp.setup {
      features = {
        inlay_hints = false,
        semantic_tokens = false,
        linked_editing_range = false,
        codelens = false,
        inline_completion = false,
      },
    }
    vim.lsp.inlay_hint.enable = original_inlay_hint_enable
    vim.lsp.semantic_tokens.enable = original_semantic_tokens_enable
    vim.lsp.linked_editing_range.enable = original_linked_editing_enable
    vim.lsp.codelens.enable = original_codelens_enable
    vim.lsp.inline_completion.enable = original_inline_completion_enable
    return calls
  end)()]]
  assert.same({
    { "inlay_hints", false },
    { "semantic_tokens", false },
    { "linked_editing_range", false },
    { "codelens", false },
    { "inline_completion", false },
  }, calls)
end

T["INIT-SIGNATURE-001 collects static and matching dynamic trigger sets"] = function()
  child = helpers.start_child()
  local state = child.lua_get [[(function()
    local astrolsp = require "astrolsp"
    local buffer = vim.api.nvim_get_current_buf()
    local second = vim.api.nvim_create_buf(true, true)
    vim.bo[buffer].filetype = "lua"
    vim.api.nvim_buf_set_name(buffer, vim.fn.tempname() .. ".lua")
    local prior_calls, events = {}, {}
    vim.lsp.handlers["client/registerCapability"] = function(err, res, ctx)
      table.insert(prior_calls, { err, res.name, ctx.client_id })
      return "prior-return"
    end
    vim.lsp.handlers["client/unregisterCapability"] = function() return "unregister-return" end
    local client = {
      id = 502,
      name = "signature",
      attached_buffers = { [buffer] = true, [second] = true },
      server_capabilities = { signatureHelpProvider = { triggerCharacters = { "(" }, retriggerCharacters = { "," } } },
      registrations = {
        ["textDocument/signatureHelp"] = {
          { registerOptions = {
            triggerCharacters = { "[" },
            retriggerCharacters = { ";" },
            documentSelector = {
              { language = "lua", scheme = "file", pattern = "**/*.lua" },
              { language = "python" },
            },
          } },
        },
      },
      supports_method = function(_, method) return method == "textDocument/signatureHelp" end,
    }
    vim.api.nvim_create_autocmd("User", {
      pattern = "AstroLspCapability",
      callback = function(args) table.insert(events, { args.data.client_id, args.data.bufnr }) end,
    })
    astrolsp.setup {}
    vim.lsp.get_client_by_id = function(id) return id == client.id and client or nil end
    vim.lsp.get_clients = function(options)
      if not options or not options.bufnr then return { client } end
      return client.attached_buffers[options.bufnr] and { client } or {}
    end
    vim.api.nvim_exec_autocmds("LspAttach", { buffer = buffer, data = { client_id = client.id } })
    local attached = {
      triggers = vim.b[buffer].signature_help_triggerCharacters,
      retriggers = vim.b[buffer].signature_help_retriggerCharacters,
    }
    client.registrations["textDocument/signatureHelp"] = {
      { registerOptions = { triggerCharacters = { "{" }, retriggerCharacters = { "}" } } },
    }
    local register_return = vim.lsp.handlers["client/registerCapability"](nil, { name = "register" }, { client_id = client.id })
    local registered = vim.b[buffer].signature_help_triggerCharacters
    local unregister_return = vim.lsp.handlers["client/unregisterCapability"](nil, {}, { client_id = client.id })
    vim.api.nvim_exec_autocmds("LspDetach", { buffer = buffer, data = { client_id = client.id } })
    return {
      attached = attached,
      registered = registered,
      register_return = register_return,
      unregister_return = unregister_return,
      prior_calls = prior_calls,
      events = events,
      detached = vim.b[buffer].signature_help_triggerCharacters,
      buffer = buffer,
      second = second,
    }
  end)()]]
  assert.same({ ["("] = true, ["["] = true }, state.attached.triggers)
  assert.same({ [","] = true, [";"] = true }, state.attached.retriggers)
  assert.same({ ["("] = true, ["{"] = true }, state.registered)
  assert.equals("prior-return", state.register_return)
  assert.equals("unregister-return", state.unregister_return)
  assert.same({ { vim.NIL, "register", 502 } }, state.prior_calls)
  local capability_events = {}
  for _, event in ipairs(state.events) do
    assert.equals(502, event[1])
    capability_events[event[2]] = (capability_events[event[2]] or 0) + 1
  end
  assert.same({ [state.buffer] = 2, [state.second] = 2 }, capability_events)
  assert.same({}, state.detached)
end

T["INIT-SIGNATURE-002 excludes negative language, scheme, and pattern selectors"] = function()
  child = helpers.start_child()
  local state = child.lua_get [[(function()
    local astrolsp = require "astrolsp"
    local buffer = vim.api.nvim_get_current_buf()
    vim.bo[buffer].filetype = "lua"
    vim.api.nvim_buf_set_name(buffer, vim.fn.tempname() .. ".lua")
    local client = {
      id = 505,
      name = "signature-selectors",
      attached_buffers = { [buffer] = true },
      server_capabilities = { signatureHelpProvider = { triggerCharacters = { "(" } } },
      registrations = {
        ["textDocument/signatureHelp"] = {
          { registerOptions = { triggerCharacters = { "p" }, documentSelector = { { language = "python" } } } },
          { registerOptions = { triggerCharacters = { "u" }, documentSelector = { { scheme = "untitled" } } } },
          { registerOptions = { triggerCharacters = { "t" }, documentSelector = { { pattern = "**/*.txt" } } } },
        },
      },
      supports_method = function(_, method) return method == "textDocument/signatureHelp" end,
    }
    astrolsp.setup {}
    vim.lsp.get_client_by_id = function(id) return id == client.id and client or nil end
    vim.lsp.get_clients = function(options)
      if options and options.bufnr and options.bufnr ~= buffer then return {} end
      return { client }
    end
    vim.api.nvim_exec_autocmds("LspAttach", { buffer = buffer, data = { client_id = client.id } })
    return vim.b[buffer].signature_help_triggerCharacters
  end)()]]
  assert.same({ ["("] = true }, state)
end

T["INIT-SIGNATURE-003 fully recomputes triggers for capability changes and detach"] = function()
  child = helpers.start_child()
  local state = child.lua_get [[(function()
    local astrolsp = require "astrolsp"
    local buffer = vim.api.nvim_get_current_buf()
    local client = {
      id = 506,
      name = "signature-recompute",
      attached_buffers = { [buffer] = true },
      server_capabilities = { signatureHelpProvider = { triggerCharacters = { "(" } } },
      registrations = {
        ["textDocument/signatureHelp"] = { { registerOptions = { triggerCharacters = { "[" } } }, },
      },
      supports_method = function(_, method) return method == "textDocument/signatureHelp" end,
    }
    vim.lsp.handlers["client/registerCapability"] = function() end
    vim.lsp.handlers["client/unregisterCapability"] = function() end
    astrolsp.setup {}
    vim.lsp.get_client_by_id = function(id) return id == client.id and client or nil end
    vim.lsp.get_clients = function(options)
      if options and options.bufnr and options.bufnr ~= buffer then return {} end
      return { client }
    end
    vim.api.nvim_exec_autocmds("LspAttach", { buffer = buffer, data = { client_id = client.id } })
    local attached = vim.b[buffer].signature_help_triggerCharacters
    client.registrations["textDocument/signatureHelp"] = { { registerOptions = { triggerCharacters = { "{" } } }, }
    vim.lsp.handlers["client/registerCapability"](nil, {}, { client_id = client.id })
    local registered = vim.b[buffer].signature_help_triggerCharacters
    client.registrations["textDocument/signatureHelp"] = {}
    vim.lsp.handlers["client/unregisterCapability"](nil, {}, { client_id = client.id })
    local unregistered = vim.b[buffer].signature_help_triggerCharacters
    vim.api.nvim_exec_autocmds("LspDetach", { buffer = buffer, data = { client_id = client.id } })
    return {
      attached = attached,
      registered = registered,
      unregistered = unregistered,
      detached = vim.b[buffer].signature_help_triggerCharacters,
    }
  end)()]]
  assert.same({ ["("] = true, ["["] = true }, state.attached)
  assert.same({ ["("] = true, ["{"] = true }, state.registered)
  assert.same({ ["("] = true }, state.unregistered)
  assert.same({}, state.detached)
end

T["INIT-DYNAMIC-001 propagates a prior capability handler error"] = function()
  child = helpers.start_child()
  local state = child.lua_get [[(function()
    local astrolsp = require "astrolsp"
    vim.lsp.handlers["client/registerCapability"] = function() error "prior capability failure" end
    astrolsp.setup {}
    local ok, message = pcall(vim.lsp.handlers["client/registerCapability"], nil, {}, { client_id = 504 })
    return { ok = ok, message = message }
  end)()]]
  assert.is_false(state.ok)
  assert.matches("prior capability failure", state.message)
end

T["INIT-SETUP-001 installs idempotent LSP wrappers across setup and module reload"] = function()
  child = helpers.start_child()
  local state = child.lua_get [[(function()
    local astrolsp = require "astrolsp"
    local buffer = vim.api.nvim_get_current_buf()
    local prior_calls = { progress = 0, register = 0, unregister = 0, hover = 0, hover_options = {} }
    local events = 0
    local client = {
      id = 503,
      name = "stacked",
      attached_buffers = { [buffer] = true },
      supports_method = function() return false end,
    }
    local returns = { progress = {}, register = {}, unregister = {}, hover = {} }
    local original_create_autocmd = vim.api.nvim_create_autocmd
    vim.api.nvim_create_autocmd = function(event, options)
      if event == "LspProgress" then error "LspProgress unavailable" end
      return original_create_autocmd(event, options)
    end
    vim.lsp.handlers["$/progress"] = function()
      prior_calls.progress = prior_calls.progress + 1
      return returns.progress
    end
    vim.lsp.handlers["client/registerCapability"] = function()
      prior_calls.register = prior_calls.register + 1
      return returns.register
    end
    vim.lsp.handlers["client/unregisterCapability"] = function()
      prior_calls.unregister = prior_calls.unregister + 1
      return returns.unregister
    end
    vim.lsp.buf.hover = function(options)
      prior_calls.hover = prior_calls.hover + 1
      table.insert(prior_calls.hover_options, options)
      return returns.hover
    end
    vim.api.nvim_create_autocmd("User", {
      pattern = "AstroLspCapability",
      callback = function() events = events + 1 end,
    })
    astrolsp.setup { defaults = { hover = { border = "first" } } }
    astrolsp.setup { defaults = { hover = { border = "second" } } }
    package.loaded.astrolsp = nil
    package.loaded["astrolsp.config"] = nil
    astrolsp = require "astrolsp"
    astrolsp.setup {}
    local restored_hover_return = vim.lsp.buf.hover { silent = "restored" }
    astrolsp.setup { defaults = { hover = { border = "latest" } } }
    vim.api.nvim_create_autocmd = original_create_autocmd
    vim.lsp.get_client_by_id = function(id) return id == client.id and client or nil end
    local progress_return = vim.lsp.handlers["$/progress"](nil, {
      token = "setup",
      value = { kind = "begin" },
    }, { client_id = client.id })
    local register_return = vim.lsp.handlers["client/registerCapability"](nil, {}, { client_id = client.id })
    local register_events = events
    events = 0
    local unregister_return = vim.lsp.handlers["client/unregisterCapability"](nil, {}, { client_id = client.id })
    local unregister_events = events
    local hover_return = vim.lsp.buf.hover { silent = true }
    return {
      prior_calls = prior_calls,
      register_events = register_events,
      unregister_events = unregister_events,
      progress_return = rawequal(progress_return, returns.progress),
      register_return = rawequal(register_return, returns.register),
      unregister_return = rawequal(unregister_return, returns.unregister),
      restored_hover_return = rawequal(restored_hover_return, returns.hover),
      hover_return = rawequal(hover_return, returns.hover),
      latest_progress = astrolsp.lsp_progress["503.string.setup"],
    }
  end)()]]
  assert.same({
    progress = 1,
    register = 1,
    unregister = 1,
    hover = 2,
    hover_options = { { silent = "restored" }, { border = "latest", silent = true } },
  }, state.prior_calls)
  assert.equals(1, state.register_events)
  assert.equals(1, state.unregister_events)
  assert.is_true(state.progress_return)
  assert.is_true(state.register_return)
  assert.is_true(state.unregister_return)
  assert.is_true(state.restored_hover_return)
  assert.is_true(state.hover_return)
  assert.same({ kind = "begin" }, state.latest_progress)
end

return T

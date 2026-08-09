local MiniTest = require "mini.test"
local helpers = require "unit_helpers"

local T = MiniTest.new_set()

local function new_astrolsp(features)
  return {
    config = {
      formatting = { format_on_save = { enabled = false } },
      features = features or {},
    },
  }
end

local function with_toggles(astrolsp, vim_replacements, callback)
  local notifications = {}
  helpers.with_module("astrolsp.toggles", {
    loaded = { astrolsp = astrolsp },
    vim = vim_replacements,
    notify = function(message, level) table.insert(notifications, { message, level }) end,
  }, function(toggles) callback(toggles, notifications) end)
end

local function with_scratch_buffers(callback)
  local buffers = {}
  local function new_buffer()
    local buffer = vim.api.nvim_create_buf(true, true)
    table.insert(buffers, buffer)
    return buffer
  end

  local ok, err = xpcall(function() callback(new_buffer) end, debug.traceback)

  for _, buffer in ipairs(buffers) do
    if vim.api.nvim_buf_is_valid(buffer) then vim.api.nvim_buf_delete(buffer, { force = true }) end
  end

  if not ok then error(err, 0) end
end

T["TGL-AF-001 [global] toggles configured autoformat state silently"] = function()
  local astrolsp = new_astrolsp()
  with_toggles(astrolsp, {}, function(toggles)
    toggles.autoformat(true)
    assert.is_true(astrolsp.config.formatting.format_on_save.enabled)
    toggles.autoformat(true)
  end)
  assert.is_false(astrolsp.config.formatting.format_on_save.enabled)
end

T["TGL-AF-001 [buffer-fallback] uses enabled fallback before toggling silently"] = function()
  local calls = {}
  local astrolsp = new_astrolsp()
  astrolsp.autoformat_available = function(bufnr)
    table.insert(calls, { "available", bufnr })
    return true
  end
  astrolsp.autoformat_enabled = function(bufnr)
    table.insert(calls, { "enabled", bufnr })
    return false
  end
  with_scratch_buffers(function(new_buffer)
    local buffer = new_buffer()

    with_toggles(astrolsp, {}, function(toggles, notifications)
      toggles.buffer_autoformat(buffer, true)
      assert.is_true(vim.b[buffer].autoformat)
      toggles.buffer_autoformat(buffer, true)
      assert.equals(0, #notifications)
    end)

    assert.is_false(vim.b[buffer].autoformat)
    assert.same({ { "available", buffer }, { "enabled", buffer }, { "available", buffer } }, calls)
  end)
end

T["TGL-AF-001 [availability] leaves buffer state unchanged when formatting is unavailable"] = function()
  local calls = {}
  local astrolsp = new_astrolsp()
  astrolsp.autoformat_available = function(bufnr)
    table.insert(calls, bufnr)
    return false
  end
  astrolsp.autoformat_enabled = function() error "fallback must not run" end
  with_scratch_buffers(function(new_buffer)
    local buffer = new_buffer()

    with_toggles(astrolsp, {}, function(toggles, notifications)
      toggles.buffer_autoformat(buffer, true)
      assert.equals(0, #notifications)
    end)

    assert.is_nil(vim.b[buffer].autoformat)
    assert.same({ buffer }, calls)
  end)
end

T["TGL-IH-001 [global-and-buffer] uses unfiltered and buffer-filtered inlay APIs"] = function()
  local calls = {}
  local global_enabled = false
  local buffer_enabled = {}
  with_scratch_buffers(function(new_buffer)
    local buffer = new_buffer()
    local astrolsp = new_astrolsp()
    local function is_enabled(filter)
      table.insert(calls, { method = "is_enabled", filter = filter })
      if filter then return buffer_enabled[filter.bufnr] or false end
      return global_enabled
    end
    local function enable(value, filter)
      table.insert(calls, { method = "enable", value = value, filter = filter })
      if filter then
        buffer_enabled[filter.bufnr] = value
      else
        global_enabled = value
      end
    end

    with_toggles(
      astrolsp,
      { lsp = { inlay_hint = { enable = enable, is_enabled = is_enabled } } },
      function(toggles, notifications)
        toggles.inlay_hints(true)
        toggles.buffer_inlay_hints(buffer, true)
        assert.equals(0, #notifications)
      end
    )

    assert.is_true(global_enabled)
    assert.is_true(buffer_enabled[buffer])
    assert.same({
      { method = "is_enabled" },
      { method = "enable", value = true },
      { method = "is_enabled" },
      { method = "is_enabled", filter = { bufnr = buffer } },
      { method = "enable", value = true, filter = { bufnr = buffer } },
      { method = "is_enabled", filter = { bufnr = buffer } },
    }, calls)
  end)
end

T["TGL-ST-001 [0.12-global] synchronizes configured state and refreshes"] = function()
  local calls = {}
  local enabled = false
  local astrolsp = new_astrolsp { semantic_tokens = false }
  local semantic_tokens = {
    enable = function(value)
      table.insert(calls, { method = "enable", value = value })
      enabled = value
    end,
    is_enabled = function()
      table.insert(calls, { method = "is_enabled" })
      return enabled
    end,
    force_refresh = function() table.insert(calls, { method = "force_refresh" }) end,
  }

  with_toggles(astrolsp, { lsp = { semantic_tokens = semantic_tokens } }, function(toggles, notifications)
    toggles.semantic_tokens(true)
    assert.equals(0, #notifications)
  end)

  assert.is_true(enabled)
  assert.is_true(astrolsp.config.features.semantic_tokens)
  assert.same({
    { method = "is_enabled" },
    { method = "enable", value = true },
    { method = "is_enabled" },
    { method = "force_refresh" },
    { method = "is_enabled" },
  }, calls)
end

T["TGL-ST-001 [0.12-buffer] scopes state, API calls, and refresh to the buffer"] = function()
  local calls = {}
  local enabled = false
  local astrolsp = new_astrolsp { semantic_tokens = true }
  with_scratch_buffers(function(new_buffer)
    local buffer = new_buffer()
    local semantic_tokens = {
      enable = function(value, filter)
        table.insert(calls, { method = "enable", value = value, filter = filter })
        enabled = value
      end,
      is_enabled = function(filter)
        table.insert(calls, { method = "is_enabled", filter = filter })
        return enabled
      end,
      force_refresh = function(bufnr) table.insert(calls, { method = "force_refresh", bufnr = bufnr }) end,
    }

    with_toggles(astrolsp, { lsp = { semantic_tokens = semantic_tokens } }, function(toggles, notifications)
      toggles.buffer_semantic_tokens(buffer, true)
      assert.equals(0, #notifications)
    end)

    assert.is_true(enabled)
    assert.is_true(astrolsp.config.features.semantic_tokens)
    assert.same({
      { method = "is_enabled", filter = { bufnr = buffer } },
      { method = "enable", value = true, filter = { bufnr = buffer } },
      { method = "force_refresh", bufnr = buffer },
      { method = "is_enabled", filter = { bufnr = buffer } },
    }, calls)
  end)
end

T["TGL-ST-001 [policy] rejects buffer semantic tokens without mutating API state"] = function()
  local calls = {}
  local astrolsp = new_astrolsp { semantic_tokens = false }
  with_scratch_buffers(function(new_buffer)
    local buffer = new_buffer()
    local semantic_tokens = {
      enable = function() table.insert(calls, "enable") end,
      is_enabled = function() table.insert(calls, "is_enabled") end,
      force_refresh = function() table.insert(calls, "force_refresh") end,
    }

    with_toggles(astrolsp, { lsp = { semantic_tokens = semantic_tokens } }, function(toggles, notifications)
      toggles.buffer_semantic_tokens(buffer, true)
      assert.equals(0, #notifications)
    end)

    assert.is_nil(vim.b[buffer].semantic_tokens)
    assert.same({}, calls)
  end)
end

T["TGL-ST-002 [0.11-supported-clients] starts and stops only supporting clients"] = function()
  local calls = {}
  local astrolsp = new_astrolsp { semantic_tokens = true }
  with_scratch_buffers(function(new_buffer)
    local buffer = new_buffer()
    local clients = {
      {
        id = 11,
        supports_method = function(_, method, bufnr)
          table.insert(calls, { method = "supports_method", client = 11, lsp_method = method, bufnr = bufnr })
          return true
        end,
      },
      {
        id = 12,
        supports_method = function(_, method, bufnr)
          table.insert(calls, { method = "supports_method", client = 12, lsp_method = method, bufnr = bufnr })
          return false
        end,
      },
    }
    local semantic_tokens = {
      enable = false,
      start = function(bufnr, client_id)
        table.insert(calls, { method = "start", bufnr = bufnr, client_id = client_id })
      end,
      stop = function(bufnr, client_id) table.insert(calls, { method = "stop", bufnr = bufnr, client_id = client_id }) end,
      force_refresh = function(bufnr) table.insert(calls, { method = "force_refresh", bufnr = bufnr }) end,
    }

    with_toggles(astrolsp, {
      lsp = {
        get_clients = function(filter)
          table.insert(calls, { method = "get_clients", filter = filter })
          return clients
        end,
        semantic_tokens = semantic_tokens,
      },
    }, function(toggles, notifications)
      toggles.buffer_semantic_tokens(buffer, true)
      toggles.buffer_semantic_tokens(buffer, true)
      assert.equals(0, #notifications)
    end)

    assert.is_false(vim.b[buffer].semantic_tokens)
    assert.same({
      { method = "get_clients", filter = { bufnr = buffer } },
      { method = "supports_method", client = 11, lsp_method = "textDocument/semanticTokens/full", bufnr = buffer },
      { method = "start", bufnr = buffer, client_id = 11 },
      { method = "supports_method", client = 12, lsp_method = "textDocument/semanticTokens/full", bufnr = buffer },
      { method = "force_refresh", bufnr = buffer },
      { method = "get_clients", filter = { bufnr = buffer } },
      { method = "supports_method", client = 11, lsp_method = "textDocument/semanticTokens/full", bufnr = buffer },
      { method = "stop", bufnr = buffer, client_id = 11 },
      { method = "supports_method", client = 12, lsp_method = "textDocument/semanticTokens/full", bufnr = buffer },
      { method = "force_refresh", bufnr = buffer },
    }, calls)
  end)
end

T["TGL-ST-002 [0.11-no-support] does not refresh without a supporting client"] = function()
  local calls = {}
  local astrolsp = new_astrolsp { semantic_tokens = true }
  with_scratch_buffers(function(new_buffer)
    local buffer = new_buffer()
    local client = {
      id = 13,
      supports_method = function(_, method, bufnr)
        table.insert(calls, { method = "supports_method", lsp_method = method, bufnr = bufnr })
        return false
      end,
    }
    local semantic_tokens = {
      enable = false,
      start = function() error "start must not run" end,
      stop = function() error "stop must not run" end,
      force_refresh = function() error "refresh must not run" end,
    }

    with_toggles(astrolsp, {
      lsp = {
        get_clients = function(filter)
          table.insert(calls, { method = "get_clients", filter = filter })
          return { client }
        end,
        semantic_tokens = semantic_tokens,
      },
    }, function(toggles, notifications)
      toggles.buffer_semantic_tokens(buffer, true)
      assert.equals(0, #notifications)
    end)

    assert.is_true(vim.b[buffer].semantic_tokens)
    assert.same({
      { method = "get_clients", filter = { bufnr = buffer } },
      { method = "supports_method", lsp_method = "textDocument/semanticTokens/full", bufnr = buffer },
    }, calls)
  end)
end

T["TGL-CL-001 [0.12-global-and-buffer] scopes CodeLens enable filters"] = function()
  local calls = {}
  local global_enabled = false
  local buffer_enabled = {}
  local astrolsp = new_astrolsp { codelens = false }
  with_scratch_buffers(function(new_buffer)
    local buffer = new_buffer()
    local codelens = {
      enable = function(value, filter)
        table.insert(calls, { method = "enable", value = value, filter = filter })
        if filter then
          buffer_enabled[filter.bufnr] = value
        else
          global_enabled = value
        end
      end,
      is_enabled = function(filter)
        table.insert(calls, { method = "is_enabled", filter = filter })
        if filter then return buffer_enabled[filter.bufnr] or false end
        return global_enabled
      end,
    }

    with_toggles(astrolsp, { lsp = { codelens = codelens } }, function(toggles, notifications)
      toggles.codelens(true)
      toggles.buffer_codelens(buffer, true)
      assert.equals(0, #notifications)
    end)

    assert.is_true(global_enabled)
    assert.is_true(buffer_enabled[buffer])
    assert.is_false(astrolsp.config.features.codelens)
    assert.same({
      { method = "is_enabled" },
      { method = "enable", value = true },
      { method = "is_enabled" },
      { method = "is_enabled", filter = { bufnr = buffer } },
      { method = "enable", value = true, filter = { bufnr = buffer } },
      { method = "is_enabled", filter = { bufnr = buffer } },
    }, calls)
  end)
end

T["TGL-CL-001 [0.11-global-fallback] toggles configured state and clears only when disabled"] = function()
  local calls = {}
  local astrolsp = new_astrolsp { codelens = false }
  local codelens = {
    enable = false,
    clear = function() table.insert(calls, { method = "clear" }) end,
  }

  with_toggles(astrolsp, { lsp = { codelens = codelens } }, function(toggles, notifications)
    toggles.codelens(true)
    assert.is_true(astrolsp.config.features.codelens)
    toggles.codelens(true)
    assert.equals(0, #notifications)
  end)

  assert.is_false(astrolsp.config.features.codelens)
  assert.same({ { method = "clear" } }, calls)
end

T["TGL-CL-CHAR-001 [characterization] leaves unsupported CodeLens buffer state untouched silently"] = function()
  local astrolsp = new_astrolsp { codelens = true }
  with_scratch_buffers(function(new_buffer)
    local buffer = new_buffer()
    local codelens = {
      enable = false,
      is_enabled = function() error "is_enabled must not run" end,
    }

    with_toggles(astrolsp, { lsp = { codelens = codelens } }, function(toggles, notifications)
      toggles.buffer_codelens(buffer, true)
      assert.equals(0, #notifications)
    end)

    assert.is_true(astrolsp.config.features.codelens)
  end)
end

T["TGL-SH-001 [global-and-buffer] toggles configured and trigger-qualified states silently"] = function()
  local astrolsp = new_astrolsp { signature_help = false }
  with_scratch_buffers(function(new_buffer)
    local buffer = new_buffer()

    with_toggles(astrolsp, {}, function(toggles, notifications)
      toggles.signature_help(true)
      assert.is_true(astrolsp.config.features.signature_help)
      vim.b[buffer].signature_help_triggerCharacters = { ["("] = true }
      toggles.buffer_signature_help(buffer, true)
      assert.is_false(vim.b[buffer].signature_help)
      assert.equals(0, #notifications)
    end)
  end)
end

T["TGL-SH-001 [missing-trigger] leaves buffer signature state unchanged silently"] = function()
  local astrolsp = new_astrolsp { signature_help = false }
  with_scratch_buffers(function(new_buffer)
    local buffer = new_buffer()

    with_toggles(astrolsp, {}, function(toggles, notifications)
      toggles.buffer_signature_help(buffer, true)
      assert.equals(0, #notifications)
    end)

    assert.is_nil(vim.b[buffer].signature_help)
  end)
end

T["TGL-NOTIFY-001 [characterization-success] records current success messages"] = function()
  local astrolsp = new_astrolsp { semantic_tokens = true, codelens = true, signature_help = false }
  astrolsp.autoformat_available = function() return true end
  astrolsp.autoformat_enabled = function() return false end
  with_scratch_buffers(function(new_buffer)
    local autoformat_buffer = new_buffer()
    local inlay_buffer = new_buffer()
    local semantic_buffer = new_buffer()
    local codelens_buffer = new_buffer()
    local signature_buffer = new_buffer()
    vim.b[signature_buffer].signature_help_triggerCharacters = { ["("] = true }
    local inlay_global, inlay_buffer_enabled = false, false
    local semantic_global, semantic_buffer_enabled = false, false
    local codelens_global, codelens_buffer_enabled = false, false
    local inlay_hint = {
      enable = function(value, filter)
        if filter then
          inlay_buffer_enabled = value
        else
          inlay_global = value
        end
      end,
      is_enabled = function(filter)
        if filter then return inlay_buffer_enabled end
        return inlay_global
      end,
    }
    local semantic_tokens = {
      enable = function(value, filter)
        if filter then
          semantic_buffer_enabled = value
        else
          semantic_global = value
        end
      end,
      is_enabled = function(filter)
        if filter then return semantic_buffer_enabled end
        return semantic_global
      end,
      force_refresh = function() end,
    }
    local codelens = {
      enable = function(value, filter)
        if filter then
          codelens_buffer_enabled = value
        else
          codelens_global = value
        end
      end,
      is_enabled = function(filter)
        if filter then return codelens_buffer_enabled end
        return codelens_global
      end,
    }

    with_toggles(astrolsp, {
      lsp = { inlay_hint = inlay_hint, semantic_tokens = semantic_tokens, codelens = codelens },
    }, function(toggles, notifications)
      toggles.autoformat()
      toggles.buffer_autoformat(autoformat_buffer)
      toggles.inlay_hints()
      toggles.buffer_inlay_hints(inlay_buffer)
      toggles.semantic_tokens()
      toggles.buffer_semantic_tokens(semantic_buffer)
      toggles.codelens()
      toggles.buffer_codelens(codelens_buffer)
      toggles.buffer_signature_help(signature_buffer)
      toggles.signature_help()

      assert.same({
        { "Global autoformatting on" },
        { "Buffer autoformatting on" },
        { "Global inlay hints on" },
        { "Buffer inlay hints on" },
        { "Global lsp semantic highlighting on" },
        { "Buffer lsp semantic highlighting on" },
        { "CodeLens on" },
        { "CodeLens on" },
        { "Buffer signature help on" },
        { "Global signature help on" },
      }, notifications)
    end)
  end)
end

T["TGL-NOTIFY-001 [characterization-rejection] records current rejection messages and warning levels"] = function()
  local astrolsp = new_astrolsp { semantic_tokens = false, codelens = true, signature_help = false }
  astrolsp.autoformat_available = function() return false end
  with_scratch_buffers(function(new_buffer)
    local autoformat_buffer = new_buffer()
    local signature_buffer = new_buffer()
    local semantic_buffer = new_buffer()
    local codelens_buffer = new_buffer()
    local semantic_tokens = {
      enable = false,
      force_refresh = function() error "refresh must not run" end,
      is_enabled = function() error "is_enabled must not run" end,
    }
    local codelens = {
      enable = false,
      is_enabled = function() error "is_enabled must not run" end,
    }

    with_toggles(
      astrolsp,
      { lsp = { semantic_tokens = semantic_tokens, codelens = codelens } },
      function(toggles, notifications)
        toggles.buffer_autoformat(autoformat_buffer)
        toggles.buffer_semantic_tokens(semantic_buffer)
        toggles.semantic_tokens(true)
        toggles.semantic_tokens()
        toggles.buffer_codelens(codelens_buffer)
        toggles.buffer_signature_help(signature_buffer)

        assert.same({
          { "No LSP attached with auto formatting" },
          { "Semantic token highlighting is disabled globally", vim.log.levels.WARN },
          { "Only available in Neovim v0.12+", vim.log.levels.WARN },
          { "Only available in Neovim v0.12+", vim.log.levels.WARN },
          { "No LSP attached with signature help triggers" },
        }, notifications)
      end
    )
  end)
end

return T

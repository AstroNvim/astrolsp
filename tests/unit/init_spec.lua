local MiniTest = require "mini.test"
local helpers = require "unit_helpers"

local T = MiniTest.new_set()

local function fresh_astrolsp(callback, options)
  options = options or {}
  options.loaded = vim.tbl_extend("force", { ["astrolsp.config"] = helpers.remove }, options.loaded or {})
  return helpers.with_module("astrolsp", options, callback)
end

local function with_buffer(callback)
  local buffer = vim.api.nvim_create_buf(true, true)
  local ok, result = xpcall(function() return callback(buffer) end, debug.traceback)
  vim.api.nvim_buf_delete(buffer, { force = true })
  if not ok then error(result, 0) end
  return result
end

local function setup_vim(overrides)
  return {
    vim = vim.tbl_deep_extend("force", {
      fn = { has = function() return 1 end },
      api = {
        nvim_create_augroup = function() return 1 end,
        nvim_create_autocmd = function() return 1 end,
      },
      lsp = {
        buf = {},
        config = function() end,
        enable = function() end,
        inlay_hint = { enable = function() end },
        semantic_tokens = { enable = function() end },
        linked_editing_range = { enable = function() end },
        codelens = { enable = function() end },
        inline_completion = { enable = function() end },
        handlers = {
          ["$/progress"] = function() end,
          ["client/registerCapability"] = function() end,
          ["client/unregisterCapability"] = function() end,
        },
      },
    }, overrides or {}),
  }
end

T["INIT-FORMAT-002 rejects disabled clients and accepts formatting clients"] = function()
  local get_clients_calls = {}
  local client = {
    name = "formatter",
    supports_method = function(_, method, buffer) return method == "textDocument/formatting" and buffer == 12 end,
  }
  fresh_astrolsp(function(astrolsp)
    astrolsp.config.formatting.disabled = {}
    assert.is_true(astrolsp.autoformat_available(12))
    astrolsp.config.formatting.disabled = { "formatter" }
    assert.is_false(astrolsp.autoformat_available(12))
    astrolsp.config.formatting.disabled = true
    assert.is_false(astrolsp.autoformat_available(12))
  end, {
    vim = {
      lsp = {
        get_clients = function(options)
          table.insert(get_clients_calls, options)
          return { client }
        end,
      },
    },
  })
  assert.same({ { bufnr = 12 }, { bufnr = 12 } }, get_clients_calls)
end

T["INIT-PROGRESS-001 [basic updates and cleanup] distinguishes token types, merges updates, and removes ended progress"] = function()
  fresh_astrolsp(function(astrolsp, context)
    astrolsp.progress { client_id = 7, params = { token = 1, value = { kind = "begin", title = "one" } } }
    astrolsp.progress { client_id = 7, params = { token = "1", value = { kind = "report", message = "two" } } }
    assert.same({ kind = "begin", title = "one" }, astrolsp.lsp_progress["7.number.1"])
    assert.same({ kind = "report", message = "two" }, astrolsp.lsp_progress["7.string.1"])
    astrolsp.progress { client_id = 7, params = { token = 1, value = { kind = "end", message = "done" } } }
    assert.same({ kind = "end", title = "one", message = "done" }, astrolsp.lsp_progress["7.number.1"])
    context.drain()
    assert.is_nil(astrolsp.lsp_progress["7.number.1"])
  end)
end

T["INIT-SERVER-001 uses server, wildcard, default, and false handlers"] = function()
  local calls = {}
  fresh_astrolsp(function(astrolsp)
    astrolsp.config.handlers = {
      lua_ls = function(server) table.insert(calls, "specific:" .. server) end,
      ["*"] = function(server) table.insert(calls, "wildcard:" .. server) end,
      disabled = false,
    }
    astrolsp.lsp_setup "lua_ls"
    astrolsp.lsp_setup "jsonls"
    astrolsp.lsp_setup "disabled"
    astrolsp.config.handlers = {}
    astrolsp.lsp_setup "default"
  end, { vim = { lsp = { enable = function(server) table.insert(calls, "default:" .. server) end } } })
  assert.same({ "specific:lua_ls", "wildcard:jsonls", "default:default" }, calls)
end

T["INIT-ATTACH-001 [configured client] filters attached clients by configured name"] = function()
  local calls = {}
  local clients = {
    [1] = { id = 1, name = "wanted" },
    [2] = { id = 2, name = "other" },
  }
  fresh_astrolsp(function(astrolsp)
    local group = vim.api.nvim_create_augroup("astrolsp_test_attach", { clear = true })
    astrolsp.add_on_attach(function(client, buffer) table.insert(calls, { client.name, buffer }) end, {
      client_name = "wanted",
      autocmd = { group = group },
    })
    local buffer = vim.api.nvim_get_current_buf()
    vim.api.nvim_exec_autocmds("LspAttach", { buffer = buffer, data = { client_id = 1 } })
    vim.api.nvim_exec_autocmds("LspAttach", { buffer = buffer, data = { client_id = 2 } })
    vim.api.nvim_del_augroup_by_id(group)
    assert.same({ { "wanted", buffer } }, calls)
  end, { vim = { lsp = { get_client_by_id = function(id) return clients[id] end } } })
end

T["INIT-FORMAT-001 respects buffer, enabled, allow, ignore, and filter precedence"] = function()
  fresh_astrolsp(function(astrolsp)
    with_buffer(function(buffer)
      vim.bo[buffer].filetype = "lua"
      local format_on_save = { enabled = true, allow_filetypes = { "lua" }, ignore_filetypes = {} }
      astrolsp.config.formatting.format_on_save = format_on_save
      assert.is_true(astrolsp.autoformat_enabled(buffer))
      format_on_save.enabled = false
      assert.is_false(astrolsp.autoformat_enabled(buffer))
      format_on_save.enabled = true
      format_on_save.allow_filetypes = { "python" }
      assert.is_false(astrolsp.autoformat_enabled(buffer))
      format_on_save.allow_filetypes = {}
      format_on_save.ignore_filetypes = { "lua" }
      assert.is_false(astrolsp.autoformat_enabled(buffer))
      format_on_save.ignore_filetypes = {}
      format_on_save.filter = function(bufnr) return bufnr ~= buffer end
      assert.is_false(astrolsp.autoformat_enabled(buffer))
      vim.b[buffer].autoformat = false
      assert.is_false(astrolsp.autoformat_enabled(buffer))
      vim.b[buffer].autoformat = true
      assert.is_true(astrolsp.autoformat_enabled(buffer))
    end)
  end)
end

T["INIT-PROGRESS-001 [typed tokens, Vim NIL, and reuse] records delayed cleanup and events"] = function()
  local events = {}
  fresh_astrolsp(function(astrolsp, context)
    astrolsp.progress { client_id = 7, params = { token = 1, value = { kind = "begin", title = "one" } } }
    astrolsp.progress { client_id = 7, params = { token = "1", value = { kind = "report", message = "two" } } }
    astrolsp.progress {
      client_id = 7,
      params = { token = 1, value = { kind = "report", title = vim.NIL, percentage = 50 } },
    }
    assert.same({ kind = "report", title = "one", percentage = 50 }, astrolsp.lsp_progress["7.number.1"])
    assert.same({ kind = "report", message = "two" }, astrolsp.lsp_progress["7.string.1"])
    astrolsp.progress { client_id = 7, params = { token = 1, value = { kind = "end", message = "done" } } }
    astrolsp.progress { client_id = 7, params = { token = 1, value = { kind = "begin", title = "reused" } } }
    astrolsp.progress { client_id = 7, params = { token = "nil", value = nil } }
    assert.equals(2, context.deferred_count())
    context.drain()
    assert.same({ kind = "begin", title = "reused" }, astrolsp.lsp_progress["7.number.1"])
    assert.is_nil(astrolsp.lsp_progress["7.string.nil"])
    assert.same({
      "AstroLspProgress",
      "AstroLspProgress",
      "AstroLspProgress",
      "AstroLspProgress",
      "AstroLspProgress",
      "AstroLspProgress",
      "AstroLspProgress",
    }, events)
  end, { vim = { api = { nvim_exec_autocmds = function(_, options) table.insert(events, options.pattern) end } } })
end

T["INIT-ATTACH-001 [missing client] ignores missing clients and filters live clients by name"] = function()
  local calls, clients = {}, { [1] = { id = 1, name = "wanted" }, [2] = { id = 2, name = "other" } }
  fresh_astrolsp(function(astrolsp)
    local group = vim.api.nvim_create_augroup("astrolsp_test_attach_missing", { clear = true })
    astrolsp.add_on_attach(function(client, buffer) table.insert(calls, { client.name, buffer }) end, {
      client_name = "wanted",
      autocmd = { group = group },
    })
    local buffer = vim.api.nvim_get_current_buf()
    for _, id in ipairs { 99, 2, 1 } do
      vim.api.nvim_exec_autocmds("LspAttach", { buffer = buffer, data = { client_id = id } })
    end
    vim.api.nvim_del_augroup_by_id(group)
    assert.same({ { "wanted", buffer } }, calls)
  end, { vim = { lsp = { get_client_by_id = function(id) return clients[id] end } } })
end

T["INIT-ATTACH-002 configures before user on_attach and tracks a client once"] = function()
  local commands, calls = {}, {}
  local client = { id = 11, name = "client", supports_method = function() return false end }
  fresh_astrolsp(function(astrolsp)
    astrolsp.config.commands = { Configured = { function() end, cond = true } }
    astrolsp.config.on_attach = function(attached, buffer)
      local configured = commands[#commands]
      table.insert(calls, { attached.id, buffer, configured and configured[1] == buffer })
    end
    astrolsp.on_attach(client, 4)
    astrolsp.on_attach(client, 5)
    assert.same({ { 4, "Configured" }, { 5, "Configured" } }, commands)
    assert.same({ { 11, 4, true }, { 11, 5, true } }, calls)
    assert.equals(client, astrolsp.attached_clients[11])
  end, {
    vim = {
      api = {
        nvim_buf_create_user_command = function(buffer, name) table.insert(commands, { buffer, name }) end,
      },
    },
  })
end

T["INIT-COND-001 applies every condition variant to user commands"] = function()
  local records = {}
  local client = {
    id = 22,
    name = "client",
    supports_method = function(_, method, buffer) return method == "textDocument/formatting" and buffer == 3 end,
  }
  fresh_astrolsp(function(astrolsp)
    local command = { function() end, cond = "textDocument/formatting", desc = "format" }
    astrolsp.config.commands = {
      Method = command,
      Boolean = { function() end, cond = true },
      Function = { function() end, cond = function(attached, buffer) return attached == client and buffer == 3 end },
      Nil = { function() end },
      Disabled = { function() end, cond = false },
    }
    astrolsp.on_attach(client, 3)
    local by_name = {}
    for _, record in ipairs(records) do
      by_name[record[1]] = { record[2], record[3] }
    end
    assert.same({
      Method = { 3, "format" },
      Boolean = { 3, nil },
      Function = { 3, nil },
      Nil = { 3, nil },
    }, by_name)
    assert.equals("textDocument/formatting", command.cond)
    assert.is_function(command[1])
  end, {
    vim = {
      api = {
        nvim_buf_create_user_command = function(buffer, name, action, options)
          table.insert(records, { name, buffer, options.desc })
          assert.is_nil(options.cond)
          assert.is_function(action)
        end,
      },
    },
  })
end

T["INIT-BUFFER-001 preserves command specs through creation and exact callback errors"] = function()
  local callback_error, created_command = {}, {}
  local client = { id = 23, name = "client", supports_method = function() return false end }
  fresh_astrolsp(function(astrolsp)
    local action = function() error(callback_error, 0) end
    local command = { action, cond = true, desc = "Fail exactly" }
    astrolsp.config.commands = { Exact = command }
    astrolsp.on_attach(client, 3)
    local ok, err = pcall(created_command.action)
    assert.is_false(ok)
    assert.is_true(rawequal(callback_error, err))
    assert.equals(action, command[1])
    assert.is_true(command.cond)
    assert.equals("Fail exactly", command.desc)
  end, {
    vim = {
      api = {
        nvim_buf_create_user_command = function(buffer, name, action, options)
          assert.is_nil(options[1])
          assert.is_nil(options.cond)
          created_command = { buffer = buffer, name = name, action = action, options = { desc = options.desc } }
        end,
      },
    },
  })
  assert.same({ buffer = 3, name = "Exact", options = { desc = "Fail exactly" } }, {
    buffer = created_command.buffer,
    name = created_command.name,
    options = created_command.options,
  })
end

T["INIT-BUFFER-004 [characterization] leaves command specs mutated after command API errors"] = function()
  local client = { id = 23, name = "client", supports_method = function() return false end }
  fresh_astrolsp(function(astrolsp)
    local command = { function() end, cond = true }
    astrolsp.config.commands = { Broken = command }
    local ok, message = pcall(astrolsp.on_attach, client, 3)
    assert.is_false(ok)
    assert.matches("command API failure", message)
    assert.is_nil(command[1])
    assert.is_nil(command.cond)
  end, { vim = { api = { nvim_buf_create_user_command = function() error "command API failure" end } } })
end

T["INIT-BUFFER-003 records mappings and which-key groups without changing config"] = function()
  local mappings, termcodes, which_key_attempts = {}, {}, 0
  local client = {
    id = 24,
    name = "client",
    supports_method = function(_, method) return method == "textDocument/formatting" end,
  }
  fresh_astrolsp(function(astrolsp)
    local mapping = { function() end, desc = "Format", cond = "textDocument/formatting" }
    local group = { desc = "LSP", cond = true }
    local caller_mappings = {
      n = {
        gq = mapping,
        ga = "<cmd>echo 'a'<cr>",
        gz = false,
        ["<Leader>l"] = group,
      },
    }
    astrolsp.setup { mappings = caller_mappings }
    astrolsp.on_attach(client, 3)
    local mappings_by_lhs = {}
    for _, mapping_record in ipairs(mappings) do
      mappings_by_lhs[mapping_record[2]] =
        { mapping_record[1], mapping_record[3], mapping_record[4], mapping_record[5] }
    end
    assert.same({
      gq = { "n", 3, "Format", true },
      ga = { "n", 3, nil, false },
    }, mappings_by_lhs)
    table.sort(termcodes)
    assert.same({ "<Leader>l", "ga", "gq", "gz" }, termcodes)
    assert.equals(1, which_key_attempts)
    assert.is_function(mapping[1])
    assert.equals("textDocument/formatting", mapping.cond)
    assert.is_nil(group[1])
    assert.is_nil(group.buffer)
    assert.is_nil(group.group)
    assert.is_nil(group.mode)
  end, {
    loaded = { ["which-key"] = helpers.remove },
    preload = {
      ["which-key"] = function()
        which_key_attempts = which_key_attempts + 1
        error "which-key unavailable"
      end,
    },
    vim = {
      fn = {
        has = function() return 0 end,
        keytrans = function(lhs) return lhs end,
      },
      api = {
        nvim_replace_termcodes = function(lhs)
          table.insert(termcodes, lhs)
          return lhs
        end,
        nvim_create_augroup = function() return 1 end,
        nvim_create_autocmd = function() return 1 end,
      },
      keymap = {
        set = function(mode, lhs, rhs, options)
          table.insert(mappings, { mode, lhs, options.buffer, options.desc, type(rhs) == "function" })
          assert.is_nil(options.cond)
        end,
      },
      lsp = {
        config = function() end,
        inlay_hint = { enable = function() end },
        semantic_tokens = { enable = function() end },
        linked_editing_range = { enable = function() end },
        codelens = { enable = function() end },
        inline_completion = { enable = function() end },
        handlers = {
          ["$/progress"] = function() end,
          ["client/registerCapability"] = function() end,
          ["client/unregisterCapability"] = function() end,
        },
      },
    },
  })
end

T["INIT-COND-001 applies every condition variant to mappings"] = function()
  local records = {}
  local client = {
    id = 25,
    name = "client",
    supports_method = function(_, method, buffer) return method == "textDocument/formatting" and buffer == 3 end,
  }
  fresh_astrolsp(function(astrolsp)
    astrolsp.config.mappings = {
      n = {
        Method = { function() end, cond = "textDocument/formatting" },
        Boolean = { function() end, cond = true },
        Function = { function() end, cond = function(attached, buffer) return attached == client and buffer == 3 end },
        Nil = { function() end },
        Disabled = { function() end, cond = false },
      },
    }
    astrolsp.on_attach(client, 3)
    local mapped_buffers = {}
    for _, record in ipairs(records) do
      mapped_buffers[record[2]] = { record[1], record[3] }
    end
    assert.same({
      Method = { "n", 3 },
      Boolean = { "n", 3 },
      Function = { "n", 3 },
      Nil = { "n", 3 },
    }, mapped_buffers)
  end, {
    vim = {
      keymap = {
        set = function(mode, lhs, _, options)
          assert.is_nil(options.cond)
          table.insert(records, { mode, lhs, options.buffer })
        end,
      },
    },
  })
end

T["INIT-MERGE-001 preserves merged formatting and feature defaults"] = function()
  fresh_astrolsp(function(astrolsp)
    astrolsp.setup {
      formatting = { format_on_save = false, timeout_ms = 250 },
      features = { signature_help = true },
    }
    assert.is_false(astrolsp.config.formatting.format_on_save.enabled)
    assert.equals(250, astrolsp.config.formatting.timeout_ms)
    assert.same({}, astrolsp.config.formatting.disabled)
    assert.is_true(astrolsp.config.features.codelens)
    assert.is_true(astrolsp.config.features.signature_help)
  end, setup_vim())
end

T["INIT-MERGE-002 [nvim-0.12] preserves current-version server ordering"] = function()
  fresh_astrolsp(function(astrolsp)
    astrolsp.config.servers = { "lua_ls", "jsonls", "lua_ls" }
    astrolsp.setup { servers = { "jsonls", "pyright", "lua_ls" } }
    assert.same({ "lua_ls", "jsonls", "pyright" }, astrolsp.config.servers)
  end, setup_vim())
end

T["INIT-FILEOPS-001 injects enabled operations into wildcard server capabilities"] = function()
  local configured = {}
  fresh_astrolsp(function(astrolsp)
    astrolsp.setup {
      file_operations = { operations = { willRename = true } },
      config = { ["*"] = { capabilities = { textDocument = { foldingRange = true } } } },
    }
    assert.is_true(configured["*"].capabilities.workspace.fileOperations.willRename)
    assert.is_true(configured["*"].capabilities.textDocument.foldingRange)
  end, setup_vim { lsp = { config = function(server, config) configured[server] = config end } })
end

T["INIT-FORMAT-003 normalizes boolean format-on-save configuration"] = function()
  fresh_astrolsp(function(astrolsp)
    astrolsp.setup {
      formatting = {
        format_on_save = true,
      },
    }
    assert.is_true(astrolsp.config.formatting.format_on_save.enabled)
  end, {
    vim = {
      api = { nvim_create_augroup = function() return 1 end, nvim_create_autocmd = function() return 1 end },
      lsp = {
        config = function() end,
        inlay_hint = { enable = function() end },
        semantic_tokens = { enable = function() end },
        linked_editing_range = { enable = function() end },
        codelens = { enable = function() end },
        inline_completion = { enable = function() end },
        handlers = {
          ["$/progress"] = function() end,
          ["client/registerCapability"] = function() end,
          ["client/unregisterCapability"] = function() end,
        },
      },
    },
  })
end

T["INIT-FORMAT-004 builds public format options without AstroLSP-only fields"] = function()
  fresh_astrolsp(function(astrolsp)
    astrolsp.setup {
      formatting = {
        format_on_save = { enabled = false },
        disabled = { "blocked" },
        timeout_ms = 321,
        async = true,
        filter = function(client) return client.name ~= "filtered" end,
      },
    }
    assert.equals(321, astrolsp.format_opts.timeout_ms)
    assert.is_true(astrolsp.format_opts.async)
    assert.is_function(astrolsp.format_opts.filter)
    assert.is_nil(astrolsp.format_opts.disabled)
    assert.is_nil(astrolsp.format_opts.format_on_save)
  end, {
    vim = {
      api = { nvim_create_augroup = function() return 1 end, nvim_create_autocmd = function() return 1 end },
      lsp = {
        config = function() end,
        inlay_hint = { enable = function() end },
        semantic_tokens = { enable = function() end },
        linked_editing_range = { enable = function() end },
        codelens = { enable = function() end },
        inline_completion = { enable = function() end },
        handlers = {
          ["$/progress"] = function() end,
          ["client/registerCapability"] = function() end,
          ["client/unregisterCapability"] = function() end,
        },
      },
    },
  })
end

T["INIT-FORMAT-005 applies disabled clients before the user filter and reads current configuration"] = function()
  local filtered_clients = {}
  fresh_astrolsp(function(astrolsp)
    astrolsp.setup {
      formatting = {
        disabled = { "blocked" },
        filter = function(client)
          table.insert(filtered_clients, client.name)
          return client.name ~= "filtered"
        end,
      },
    }
    assert.is_false(astrolsp.format_opts.filter { name = "blocked" })
    assert.same({}, filtered_clients)
    assert.is_false(astrolsp.format_opts.filter { name = "filtered" })
    assert.is_true(astrolsp.format_opts.filter { name = "allowed" })
    assert.same({ "filtered", "allowed" }, filtered_clients)
    astrolsp.config.formatting.disabled = true
    assert.is_false(astrolsp.format_opts.filter { name = "allowed" })
    assert.same({ "filtered", "allowed" }, filtered_clients)
    astrolsp.config.formatting.disabled = {}
    astrolsp.config.formatting.filter = function(client) return client.name == "newly-allowed" end
    assert.is_false(astrolsp.format_opts.filter { name = "allowed" })
    assert.is_true(astrolsp.format_opts.filter { name = "newly-allowed" })
  end, {
    vim = {
      api = { nvim_create_augroup = function() return 1 end, nvim_create_autocmd = function() return 1 end },
      lsp = {
        config = function() end,
        inlay_hint = { enable = function() end },
        semantic_tokens = { enable = function() end },
        linked_editing_range = { enable = function() end },
        codelens = { enable = function() end },
        inline_completion = { enable = function() end },
        handlers = {
          ["$/progress"] = function() end,
          ["client/registerCapability"] = function() end,
          ["client/unregisterCapability"] = function() end,
        },
      },
    },
  })
end

T["INIT-DEFAULTS-001 applies configured LSP buffer defaults"] = function()
  local hover_calls = {}
  fresh_astrolsp(function(astrolsp)
    astrolsp.setup {
      defaults = { hover = { border = "rounded", silent = true } },
    }
    vim.lsp.buf.hover { silent = false, focusable = false }
    assert.same({ border = "rounded", silent = false, focusable = false }, hover_calls[1])
  end, setup_vim { lsp = { buf = { hover = function(options) table.insert(hover_calls, options) end } } })
end

T["INIT-HANDLER-001 installs configured LSP handlers"] = function()
  local configured_handler = function() end
  fresh_astrolsp(function(astrolsp)
    astrolsp.setup { lsp_handlers = { ["textDocument/publishDiagnostics"] = configured_handler } }
    assert.equals(configured_handler, vim.lsp.handlers["textDocument/publishDiagnostics"])
  end, setup_vim { lsp = { handlers = { ["textDocument/publishDiagnostics"] = function() end } } })
end

T["INIT-MERGE-002 [nvim-0.11] deduplicates the force-merged server order"] = function()
  fresh_astrolsp(function(astrolsp)
    astrolsp.config.servers = { "lua_ls", "jsonls", "lua_ls" }
    astrolsp.setup { servers = { "jsonls", "pyright", "lua_ls" } }
    assert.same({ "jsonls", "pyright", "lua_ls" }, astrolsp.config.servers)
  end, {
    vim = {
      fn = { has = function() return 0 end },
      api = { nvim_create_augroup = function() return 1 end, nvim_create_autocmd = function() return 1 end },
      lsp = {
        config = function() end,
        enable = function() end,
        inlay_hint = { enable = function() end },
        semantic_tokens = { enable = function() end },
        linked_editing_range = { enable = function() end },
        codelens = { enable = function() end },
        inline_completion = { enable = function() end },
        handlers = {
          ["$/progress"] = function() end,
          ["client/registerCapability"] = function() end,
          ["client/unregisterCapability"] = function() end,
        },
      },
    },
  })
end

return T

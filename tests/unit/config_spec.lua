local MiniTest = require "mini.test"
local helpers = require "unit_helpers"

local T = MiniTest.new_set()

T["CFG-DEFAULT-001 exposes documented default leaves"] = function()
  helpers.with_module("astrolsp.config", nil, function(config)
    assert.same({
      codelens = true,
      inlay_hints = false,
      inline_completion = false,
      linked_editing_range = false,
      semantic_tokens = true,
      signature_help = false,
    }, config.features)
    assert.same({ timeout = 10000, operations = {} }, config.file_operations)
    assert.same({ format_on_save = { enabled = true }, disabled = {} }, config.formatting)
    assert.same({}, config.autocmds)
    assert.same({}, config.commands)
    assert.same({}, config.config)
    assert.same({}, config.defaults)
    assert.same({}, config.handlers)
    assert.same({}, config.lsp_handlers)
    assert.same({}, config.mappings)
    assert.same({}, config.servers)
    assert.is_nil(config.on_attach)
  end)
end

T["CFG-FRESH-001 creates independent defaults after an isolated reload"] = function()
  helpers.with_module("astrolsp.config", nil, function(first)
    first.features.codelens = false
    first.formatting.disabled[1] = "fake"
    package.loaded["astrolsp.config"] = nil
    local second = require "astrolsp.config"
    assert.is_true(second.features.codelens)
    assert.same({}, second.formatting.disabled)
  end)
end

return T

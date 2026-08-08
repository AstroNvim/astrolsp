local MiniTest = require "mini.test"
local config = require "config"

local T = MiniTest.new_set()

local function read_file(path)
  local file = assert(io.open(path, "rb"))
  local contents = assert(file:read "*a")
  file:close()
  return contents
end

local function make_target_body(makefile, target)
  local start = assert(makefile:find("\n" .. target .. ":\n", 1, true))
  local body_start = start + #target + 3
  local finish = makefile:find("\n[%w-]+:\n", body_start)
  return makefile:sub(body_start, finish and finish - 1 or #makefile)
end

T["LAZY-CONTRACT-001 declares the plugin name and exact opts_extend paths"] = function()
  local spec = assert(loadfile(config.root .. "/lazy.lua"))()
  assert.equals("AstroNvim/astrolsp", spec[1])
  assert.same({
    "formatting.disabled",
    "formatting.format_on_save.allow_filetypes",
    "formatting.format_on_save.ignore_filetypes",
    "servers",
  }, spec.opts_extend)
end

T["MAKE-TARGET-001 declares prepared public targets with exact spec commands"] = function()
  local makefile = read_file(config.root .. "/Makefile")
  local public_targets = {
    "test",
    "test-unit",
    "test-semantic",
    "test-semantic-attach",
    "test-semantic-lifecycle",
    "test-unit-environment",
    "test-unit-config",
    "test-unit-init",
    "test-unit-file-operations",
    "test-unit-toggles",
    "test-unit-health",
    "test-contracts",
  }
  local target_bodies = {
    test = "\t@nvim -l tests/minit.lua --minitest tests/unit/*.lua tests/semantic/*.lua\n",
    ["test-unit"] = "\t@nvim -l tests/minit.lua --minitest tests/unit/*.lua\n",
    ["test-semantic"] = "\t@nvim -l tests/minit.lua --minitest tests/semantic/*.lua\n",
    ["test-semantic-attach"] = "\t@nvim -l tests/minit.lua --minitest tests/semantic/attach_spec.lua\n",
    ["test-semantic-lifecycle"] = "\t@nvim -l tests/minit.lua --minitest tests/semantic/init_spec.lua\n",
    ["test-unit-environment"] = "\t@nvim -l tests/minit.lua --minitest tests/unit/test_environment_spec.lua tests/unit/unit_helpers_spec.lua tests/unit/helpers_spec.lua\n",
    ["test-unit-config"] = "\t@nvim -l tests/minit.lua --minitest tests/unit/config_spec.lua\n",
    ["test-unit-init"] = "\t@nvim -l tests/minit.lua --minitest tests/unit/init_spec.lua\n",
    ["test-unit-file-operations"] = "\t@nvim -l tests/minit.lua --minitest tests/unit/file_operations_spec.lua\n",
    ["test-unit-toggles"] = "\t@nvim -l tests/minit.lua --minitest tests/unit/toggles_spec.lua\n",
    ["test-unit-health"] = "\t@nvim -l tests/minit.lua --minitest tests/unit/health_spec.lua\n",
    ["test-contracts"] = "\t@nvim -l tests/minit.lua --minitest tests/unit/contracts_spec.lua\n",
  }
  local targets = assert(makefile:match "TEST_TARGETS := ([^\n]+)")

  assert.equals(table.concat(public_targets, " "), targets)
  assert.is_truthy(makefile:find("$(TEST_TARGETS): test-prepare", 1, true))
  for target, expected_body in pairs(target_bodies) do
    assert.equals(expected_body, make_target_body(makefile, target))
  end
end

T["ENV-CONTRACT-001 enables recovery only through the CI preparation entry point"] = function()
  local bootstrap = read_file(config.root .. "/tests/bootstrap.lua")
  local prepare = read_file(config.root .. "/tests/prepare_test_environment.lua")

  assert.is_truthy(prepare:find('require("test_environment").enable_ci_recovery()', 1, true))
  assert.is_truthy(bootstrap:find("ci_recovery = environment.is_ci_recovery_enabled()", 1, true))
  assert.is_nil(bootstrap:find("TEST_PREPARE_CI", 1, true))
end

return T

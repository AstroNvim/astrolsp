local MiniTest = require "mini.test"
local config = require "config"

local T = MiniTest.new_set()

local SHARED_WORKFLOW_REF = "main"

local function read_file(path)
  local file = assert(io.open(path, "rb"))
  local contents = assert(file:read "*a")
  file:close()
  return contents
end

local function dedent(block, width)
  local indentation = string.rep(" ", width)
  return (block:gsub("^" .. indentation, ""):gsub("\n" .. indentation, "\n"):gsub("\n+$", ""))
end

local function as_set(values)
  local set = {}
  for _, value in ipairs(values) do
    assert.is_nil(set[value])
    set[value] = true
  end
  return set
end

local function extract_two_space_job_names(workflow)
  local jobs = assert(workflow:match "\njobs:\n(.*)")
  local names = {}
  for name in ("\n" .. jobs):gmatch "\n  ([_%a][_%w-]*):\n" do
    table.insert(names, name)
  end
  return names
end

local function workflow_job(workflow, name)
  local start = assert(workflow:find("\n  " .. name .. ":\n", 1, true))
  local finish = workflow:find("\n  [_%a][_%w-]*:\n", start + 1)
  return workflow:sub(start, finish and finish - 1 or #workflow)
end

local function extract_trigger_block(workflow)
  local start = assert(workflow:find("\non:\n", 1, true))
  local body_start = start + #"\non:\n"
  local finish = workflow:find("\n[%w][%w_-]*:\n", body_start)
  return dedent(workflow:sub(body_start, finish and finish - 1 or #workflow), 2)
end

local function extract_guard(block)
  for line in block:gmatch "[^\n]+" do
    local value = line:match "^[ \t]*if:%s*(.-)%s*$"
    if value then return value end
  end
end

local function extract_with_block(block)
  local _, finish, indentation = assert(block:find "\n([ \t]*)with:\n")
  local body_start = finish + 1
  local next_property = block:find("\n" .. indentation .. "[%w-]+:", body_start)
  return dedent(block:sub(body_start, next_property and next_property - 1 or #block), #indentation + 2)
end

local function extract_uses(block) return assert(block:match "\n    uses: ([^\n]+)") end

local function permission_block(job)
  local start = assert(job:find("\n    permissions:\n", 1, true))
  local body_start = start + #"\n    permissions:\n"
  local finish = job:find("\n    [%w-]+:", body_start)
  return (job:sub(body_start, finish and finish - 1 or #job):gsub("\n+$", ""))
end

local function make_target_body(makefile, target)
  local start = assert(makefile:find("\n" .. target .. ":\n", 1, true))
  local body_start = start + #target + 3
  local finish = makefile:find("\n[%w-]+:\n", body_start)
  return makefile:sub(body_start, finish and finish - 1 or #makefile)
end

local function assert_thin_reusable_job(job)
  assert.is_nil(job:find("runs-on:", 1, true))
  assert.is_nil(job:find("steps:", 1, true))
  assert.is_nil(job:find("actions/", 1, true))
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

T["MAKE-TARGET-001 declares the shared Neovim test target contract"] = function()
  local makefile = read_file(config.root .. "/Makefile")
  local required_targets = {
    "test-fingerprint",
    "test-prepare",
    "test-clear",
    "test-update-deps",
    "test",
    "test-semantic",
  }

  local phony = assert(makefile:match "%.PHONY: ([^\n]+)")
  for _, target in ipairs(required_targets) do
    assert.is_truthy(phony:find(target, 1, true))
  end
  assert.equals("\t@nvim -l tests/print_fingerprint.lua\n", make_target_body(makefile, "test-fingerprint"))
  assert.is_nil(makefile:match "$(TEST_TARGETS): test%-fingerprint")
  assert.is_truthy(makefile:find("$(TEST_TARGETS): test-prepare", 1, true))
  assert.equals("\t@$(MAKE) test-clear\n\t@$(MAKE) test-prepare\n", make_target_body(makefile, "test-update-deps"))

  local fingerprint_script = read_file(config.root .. "/tests/print_fingerprint.lua")
  assert.equals(
    table.concat({
      'local tests_dir = vim.fs.dirname(debug.getinfo(1, "S").source:sub(2))',
      'package.path = tests_dir .. "/?.lua;" .. package.path',
      'io.stdout:write(require("test_environment").specification_hash, "\\n")',
      "",
    }, "\n"),
    fingerprint_script
  )
end

T["CI-CONTRACT-001 declares thin callers for shared workflows"] = function()
  local workflow = read_file(config.root .. "/.github/workflows/ci.yml")
  local plugin_ci = "AstroNvim/.github/.github/workflows/plugin_ci.yml@" .. SHARED_WORKFLOW_REF
  local neovim_testing = "AstroNvim/.github/.github/workflows/neovim_testing.yml@" .. SHARED_WORKFLOW_REF
  local validate_pr = "AstroNvim/.github/.github/workflows/validate_pr.yml@" .. SHARED_WORKFLOW_REF
  local ci = workflow_job(workflow, "CI")
  local tests = workflow_job(workflow, "Tests")
  local release = workflow_job(workflow, "Release")
  local pr_validation = workflow_job(workflow, "PR")

  assert.equals("AstroLSP", assert(workflow:match "name: ([^\n]+)"))
  assert.same(as_set { "CI", "Tests", "Release", "PR" }, as_set(extract_two_space_job_names(workflow)))
  assert.equals(
    table.concat({
      "push:",
      "  branches: [main]",
      "pull_request:",
      "pull_request_target:",
      "  types: [opened, edited, synchronize, labeled, unlabeled]",
      "schedule:",
      '  - cron: "0 6 * * *"',
      '  - cron: "0 8 * * 1"',
    }, "\n"),
    extract_trigger_block(workflow)
  )

  assert.equals("${{ github.event_name == 'pull_request' }}", extract_guard(ci))
  assert.equals(plugin_ci, extract_uses(ci))
  assert.equals("      contents: read", permission_block(ci))
  assert.equals("plugin_name: ${{ github.event.repository.name }}\nis_production: false", extract_with_block(ci))
  assert.is_nil(ci:find("secrets:", 1, true))
  assert_thin_reusable_job(ci)

  assert.equals(
    "${{ github.event_name == 'push' || github.event_name == 'pull_request' || github.event_name == 'schedule' }}",
    extract_guard(tests)
  )
  assert.equals(neovim_testing, extract_uses(tests))
  assert.equals("      contents: read", permission_block(tests))
  assert.equals(
    'minimum_neovim: "0.11.0"\nstable_neovim: "0.12.4"\ncache_rotation: "1"\ntimeout_minutes: 30',
    extract_with_block(tests)
  )
  assert.is_nil(tests:find("secrets:", 1, true))
  assert_thin_reusable_job(tests)

  assert.equals("${{ github.event_name == 'push' }}", extract_guard(release))
  assert.equals("Tests", assert(release:match "\n    needs: ([^\n]+)"))
  assert.equals(plugin_ci, extract_uses(release))
  assert.equals("      contents: write\n      pull-requests: write", permission_block(release))
  assert.is_truthy(
    release:find(
      "concurrency:\n      group: ${{ github.event.repository.name }}-release\n      cancel-in-progress: false",
      1,
      true
    )
  )
  assert.equals("plugin_name: ${{ github.event.repository.name }}\nis_production: true", extract_with_block(release))
  assert.is_truthy(release:find("secrets:\n      RELEASE_TOKEN: ${{ secrets.RELEASE_TOKEN }}", 1, true))
  assert_thin_reusable_job(release)

  assert.equals("${{ github.event_name == 'pull_request_target' }}", extract_guard(pr_validation))
  assert.equals(validate_pr, extract_uses(pr_validation))
  assert.equals("      pull-requests: read", permission_block(pr_validation))
  assert.equals("conventional_title: true\nrequire_scope: false", extract_with_block(pr_validation))
  assert.is_nil(pr_validation:find("secrets:", 1, true))
  assert_thin_reusable_job(pr_validation)
end

return T

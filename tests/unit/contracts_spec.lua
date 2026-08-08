local MiniTest = require "mini.test"
local config = require "config"

local T = MiniTest.new_set()

local ACTIONS_SHA = {
  astro_workflows = "97cdc3810853afdcccf8e40f7262bd5ec397c8fa",
  cache = "0057852bfaa89a56745cba8c7296529d2fc39830",
  checkout = "11d5960a326750d5838078e36cf38b85af677262",
  semantic_pr = "48f256284bd46cdaab1048c3721360e808335d50",
  setup_vim = "febef33995d6649302e9d88dda81e071b68f16a7",
}

local ARCHIVE_SHA256 = {
  actionlint = "8aca8db96f1b94770f1b0d72b6dddcb1ebb8123cb3712530b08cc387b349a3d8",
  neovim = "012bf3fcac5ade43914df3f174668bf64d05e049a4f032a388c027b1ebd78628",
}

local CACHE_SPECIFICATION_FILES = {
  "Makefile",
  "tests/bootstrap.lua",
  "tests/clear_test_environment.lua",
  "tests/config.lua",
  "tests/fixtures/init.lua",
  "tests/helpers.lua",
  "tests/minit.lua",
  "tests/prepare_test_environment.lua",
  "tests/test_environment.lua",
  "tests/unit_helpers.lua",
  "tests/semantic/attach_spec.lua",
  "tests/semantic/init_spec.lua",
  "tests/unit/config_spec.lua",
  "tests/unit/contracts_spec.lua",
  "tests/unit/file_operations_spec.lua",
  "tests/unit/health_spec.lua",
  "tests/unit/helpers_spec.lua",
  "tests/unit/init_spec.lua",
  "tests/unit/test_environment_spec.lua",
  "tests/unit/toggles_spec.lua",
  "tests/unit/unit_helpers_spec.lua",
}

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

local function extract_uses_set(block)
  local uses = {}
  for action in block:gmatch "\n[ \t]*%-?[ \t]*uses: ([^\n]+)" do
    assert.is_nil(uses[action])
    uses[action] = true
  end
  return uses
end

local function named_step(job, name)
  local prefix = "\n      - name: " .. name .. "\n"
  local start = assert(job:find(prefix, 1, true))
  local finish = job:find("\n      - ", start + #prefix, true)
  return job:sub(start, finish and finish - 1 or #job)
end

local function named_step_body(job, name)
  local step = named_step(job, name)
  local prefix = "\n      - name: " .. name .. "\n"
  return dedent(step:sub(#prefix + 1), 8)
end

local function extract_with_block(block)
  local _, finish, indentation = assert(block:find "\n([ \t]*)with:\n")
  local body_start = finish + 1
  local next_property = block:find("\n" .. indentation .. "[%w-]+:", body_start)
  return dedent(block:sub(body_start, next_property and next_property - 1 or #block), #indentation + 2)
end

local function extract_guard(block)
  for line in block:gmatch "[^\n]+" do
    local value = line:match "^[ \t]*if:%s*(.-)%s*$"
    if value then return value end
  end
end

local function make_target_body(makefile, target)
  local start = assert(makefile:find("\n" .. target .. ":\n", 1, true))
  local body_start = start + #target + 3
  local finish = makefile:find("\n[%w-]+:\n", body_start)
  return makefile:sub(body_start, finish and finish - 1 or #makefile)
end

local function permission_block(job)
  local start = assert(job:find("\n    permissions:\n", 1, true))
  local body_start = start + #"\n    permissions:\n"
  local finish = job:find("\n    [%w-]+:", body_start)
  return (job:sub(body_start, finish and finish - 1 or #job):gsub("\n+$", ""))
end

local function assert_exact_permissions(job, expected) assert.equals(expected, permission_block(job)) end

local function assert_exact_uses(block, expected) assert.same(as_set(expected), extract_uses_set(block)) end

local function assert_pinned_checkout(job)
  assert.is_truthy(
    job:find(
      "uses: actions/checkout@" .. ACTIONS_SHA.checkout .. " # v4\n        with:\n          persist-credentials: false",
      1,
      true
    )
  )
  assert.is_nil(job:find("uses: actions/checkout@v4", 1, true))
end

local function cache_key(prefix)
  local specifications = {}
  for _, file in ipairs(CACHE_SPECIFICATION_FILES) do
    table.insert(specifications, "'" .. file .. "'")
  end
  return prefix
    .. "-${{ runner.os }}-${{ runner.arch }}-nvim-${{ env.NVIM_VERSION }}-schema-${{ env.TEST_ENVIRONMENT_SCHEMA }}-rotation-${{ env.TEST_ENVIRONMENT_CACHE_ROTATION }}-spec-${{ hashFiles("
    .. table.concat(specifications, ", ")
    .. ") }}"
end

local function assert_cache_pair(job, restore_name, save_name, prefix)
  local restore = named_step(job, restore_name)
  local save = named_step(job, save_name)
  local expected_with = "path: .tests\nkey: " .. cache_key(prefix)

  assert.equals("test-environment-cache", assert(restore:match "\n        id: ([^\n]+)"))
  assert.is_nil(extract_guard(restore))
  assert_exact_uses(restore, { "actions/cache/restore@" .. ACTIONS_SHA.cache .. " # v4" })
  assert.equals(expected_with, extract_with_block(restore))

  assert.equals("steps.test-environment-cache.outputs.cache-hit != 'true'", extract_guard(save))
  assert_exact_uses(save, { "actions/cache/save@" .. ACTIONS_SHA.cache .. " # v4" })
  assert.equals(expected_with, extract_with_block(save))
end

local PREFLIGHT_STEP_BODY = table.concat({
  "shell: bash",
  "run: |",
  "  git diff --check",
  "  git diff --exit-code",
}, "\n")

local IMMUTABILITY_STEP_BODY = table.concat({
  "shell: bash",
  "run: |",
  "  git diff --check",
  "  git diff --exit-code",
  '  test -z "$(git ls-files --others --exclude-standard)"',
}, "\n")

local function assert_repository_integrity_steps(job, always)
  assert.equals(PREFLIGHT_STEP_BODY, named_step_body(job, "Run repository preflight"))

  local expected = IMMUTABILITY_STEP_BODY
  if always then expected = "if: ${{ always() }}\n" .. expected end
  assert.equals(expected, named_step_body(job, "Verify repository immutability"))
  local expected_guard = always and "${{ always() }}" or nil
  local actual_guard = extract_guard(named_step(job, "Verify repository immutability"))
  assert.equals(expected_guard, actual_guard)
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

T["CI-CONTRACT-001 declares exact workflow jobs, triggers, reusable calls, and PR validation"] = function()
  local workflow = read_file(config.root .. "/.github/workflows/ci.yml")
  local source_ci = workflow_job(workflow, "CI")
  local release = workflow_job(workflow, "Release")
  local pr_validation = workflow_job(workflow, "PR")
  local reusable_plugin_ci = "AstroNvim/.github/.github/workflows/plugin_ci.yml@"
    .. ACTIONS_SHA.astro_workflows
    .. " # v1"
  local parser_fixture = [[
name: Parser fixture
on:
  push:
jobs:
  security_check:
    runs-on: ubuntu-latest
  release-job:
    runs-on: ubuntu-latest
]]

  assert.same({ "security_check", "release-job" }, extract_two_space_job_names(parser_fixture))
  assert.is_nil(workflow_job(parser_fixture, "security_check"):find("release-job", 1, true))
  assert.equals("AstroLSP", assert(workflow:match "name: ([^\n]+)"))
  assert.same(
    as_set { "CI", "Release", "Tests", "Semantic", "Nightly", "Dependency-Refresh", "PR" },
    as_set(extract_two_space_job_names(workflow))
  )
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

  assert.equals("${{ github.event_name == 'pull_request' }}", extract_guard(source_ci))
  assert_exact_permissions(source_ci, "      contents: read")
  assert_exact_uses(source_ci, { reusable_plugin_ci })
  assert.equals("plugin_name: ${{ github.event.repository.name }}\nis_production: false", extract_with_block(source_ci))
  assert.is_nil(source_ci:find("secrets:", 1, true))

  assert.equals("${{ github.event_name == 'push' }}", extract_guard(release))
  assert_exact_permissions(release, "      contents: write\n      pull-requests: write")
  assert_exact_uses(release, { reusable_plugin_ci })
  assert.equals("plugin_name: ${{ github.event.repository.name }}\nis_production: true", extract_with_block(release))
  assert.is_truthy(release:find("secrets:\n      RELEASE_TOKEN: ${{ secrets.RELEASE_TOKEN }}", 1, true))
  assert.is_nil(release:find("secrets: inherit", 1, true))

  assert.equals("${{ github.event_name == 'pull_request_target' }}", extract_guard(pr_validation))
  assert_exact_permissions(pr_validation, "      pull-requests: read")
  assert_exact_uses(pr_validation, { "amannn/action-semantic-pull-request@" .. ACTIONS_SHA.semantic_pr .. " # v6" })
  assert.equals(
    table.concat({
      "requireScope: false",
      "types: |",
      "  build",
      "  chore",
      "  ci",
      "  docs",
      "  feat",
      "  fix",
      "  merge",
      "  perf",
      "  refactor",
      "  revert",
      "  style",
      "  test",
      "  wip",
      "ignoreLabels: |",
      "  autorelease: pending",
    }, "\n"),
    extract_with_block(pr_validation)
  )
  assert.is_truthy(pr_validation:find("env:\n          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}", 1, true))
  assert.is_nil(pr_validation:find("secrets:", 1, true))
  assert.is_nil(pr_validation:find("actions/checkout", 1, true))
  assert.is_nil(pr_validation:find("run:", 1, true))
  assert.is_nil(pr_validation:find("shell:", 1, true))
end

T["CI-CONTRACT-002 pins test jobs, cache pairs, and repository integrity steps"] = function()
  local workflow = read_file(config.root .. "/.github/workflows/ci.yml")
  local tests = workflow_job(workflow, "Tests")
  local semantic = workflow_job(workflow, "Semantic")
  local nightly = workflow_job(workflow, "Nightly")
  local refresh = workflow_job(workflow, "Dependency-Refresh")
  local cache_sha = ACTIONS_SHA.cache .. " # v4"

  assert.is_truthy(workflow:find('TEST_ENVIRONMENT_SCHEMA: "3"', 1, true))
  assert.is_truthy(workflow:find('TEST_ENVIRONMENT_CACHE_ROTATION: "1"', 1, true))

  assert.equals("${{ github.event_name == 'push' || github.event_name == 'pull_request' }}", extract_guard(tests))
  assert.equals("${{ github.event_name == 'push' || github.event_name == 'pull_request' }}", extract_guard(semantic))
  assert.equals(
    "${{ github.event_name == 'schedule' && github.event.schedule == '0 6 * * *' }}",
    extract_guard(nightly)
  )
  assert.equals(
    "${{ github.event_name == 'schedule' && github.event.schedule == '0 8 * * 1' }}",
    extract_guard(refresh)
  )

  assert.equals(
    table.concat({
      "shell: bash",
      "run: |",
      '  nvim_archive_sha256="' .. ARCHIVE_SHA256.neovim .. '"',
      "  curl --fail --location --silent --show-error --retry 3 \\",
      [[    "https://github.com/neovim/neovim/releases/download/v${NVIM_VERSION}/nvim-linux-x86_64.tar.gz" \]],
      "    --output /tmp/nvim.tar.gz",
      '  echo "${nvim_archive_sha256}  /tmp/nvim.tar.gz" | sha256sum --check --status',
      "  tar --extract --gzip --file /tmp/nvim.tar.gz --directory /tmp",
      '  echo "/tmp/nvim-linux-x86_64/bin" >> "$GITHUB_PATH"',
      '  export PATH="/tmp/nvim-linux-x86_64/bin:$PATH"',
      '  test "$(nvim --version | head -n 1)" = "NVIM v${NVIM_VERSION}"',
    }, "\n"),
    named_step_body(tests, "Install and verify Neovim")
  )
  assert.equals(
    table.concat({
      "shell: bash",
      "run: |",
      "  cargo install stylua --version 2.5.2 --locked",
      "  cargo install selene --version 0.31.0 --locked",
      '  actionlint_version="1.7.12"',
      '  actionlint_archive_sha256="' .. ARCHIVE_SHA256.actionlint .. '"',
      "  curl --fail --location --silent --show-error --retry 3 \\",
      [[    "https://github.com/rhysd/actionlint/releases/download/v${actionlint_version}/actionlint_${actionlint_version}_linux_amd64.tar.gz" \]],
      "    --output /tmp/actionlint.tar.gz",
      '  echo "${actionlint_archive_sha256}  /tmp/actionlint.tar.gz" | sha256sum --check --status',
      "  mkdir --parents /tmp/actionlint",
      "  tar --extract --gzip --file /tmp/actionlint.tar.gz --directory /tmp/actionlint actionlint",
      "  install /tmp/actionlint/actionlint /usr/local/bin/actionlint",
      '  test "$(actionlint -version)" = "$actionlint_version"',
    }, "\n"),
    named_step_body(tests, "Install pinned test linters")
  )
  assert.equals(
    table.concat({
      "shell: bash",
      "run: |",
      "  stylua --check tests",
      "  selene tests",
      "  actionlint .github/workflows/*.yml",
    }, "\n"),
    named_step_body(tests, "Run static checks")
  )
  assert.equals(
    table.concat({
      "shell: bash",
      "run: |",
      "  make test",
      "  make test",
    }, "\n"),
    named_step_body(tests, "Run the full suite twice")
  )

  assert.is_truthy(semantic:find("fail-fast: false", 1, true))
  for _, fact in ipairs { "ubuntu-latest", "macos-latest", "windows-latest", 'neovim: "0.11.0"', 'neovim: "0.12.4"' } do
    assert.is_truthy(semantic:find(fact, 1, true))
  end
  assert.equals(
    "neovim: true\nversion: v${{ matrix.neovim }}",
    extract_with_block(named_step(semantic, "Install Neovim"))
  )
  assert.equals("neovim: true\nversion: nightly", extract_with_block(named_step(nightly, "Install Neovim nightly")))
  assert.equals(
    "neovim: true\nversion: v${{ env.NVIM_VERSION }}",
    extract_with_block(named_step(refresh, "Install Neovim"))
  )
  assert.equals(
    'shell: bash\nrun: test "$(nvim --version | head -n 1)" = "NVIM v${NVIM_VERSION}"',
    named_step_body(semantic, "Verify Neovim version")
  )
  assert.equals(
    'shell: bash\nrun: test "$(nvim --version | head -n 1)" = "NVIM v${NVIM_VERSION}"',
    named_step_body(refresh, "Verify Neovim version")
  )
  assert.equals(
    "if: runner.os == 'Windows'\nshell: bash\nrun: |\n  command -v git\n  command -v env",
    named_step_body(semantic, "Verify Windows command prerequisites")
  )

  assert.is_truthy(nightly:find("continue-on-error: true", 1, true))
  assert.equals("shell: bash\nrun: make test-prepare-ci", named_step_body(nightly, "Prepare the test environment"))
  assert.equals(
    "shell: bash\nrun: |\n  make test-clear\n  make test-prepare",
    named_step_body(refresh, "Clear and rebuild the test environment")
  )
  assert.equals("shell: bash\nrun: make test-semantic", named_step_body(refresh, "Run semantic smoke suite"))

  for _, job in ipairs { tests, semantic, nightly, refresh } do
    assert.is_truthy(job:find("timeout-minutes: 30", 1, true))
    assert_exact_permissions(job, "      contents: read")
    assert_pinned_checkout(job)
  end

  assert_exact_uses(tests, {
    "actions/checkout@" .. ACTIONS_SHA.checkout .. " # v4",
    "actions/cache/restore@" .. cache_sha,
    "actions/cache/save@" .. cache_sha,
  })
  assert_exact_uses(semantic, {
    "actions/checkout@" .. ACTIONS_SHA.checkout .. " # v4",
    "rhysd/action-setup-vim@" .. ACTIONS_SHA.setup_vim .. " # v1",
    "actions/cache/restore@" .. cache_sha,
    "actions/cache/save@" .. cache_sha,
  })
  assert_exact_uses(nightly, {
    "actions/checkout@" .. ACTIONS_SHA.checkout .. " # v4",
    "rhysd/action-setup-vim@" .. ACTIONS_SHA.setup_vim .. " # v1",
    "actions/cache/restore@" .. cache_sha,
    "actions/cache/save@" .. cache_sha,
  })
  assert_exact_uses(refresh, {
    "actions/checkout@" .. ACTIONS_SHA.checkout .. " # v4",
    "rhysd/action-setup-vim@" .. ACTIONS_SHA.setup_vim .. " # v1",
  })

  assert_cache_pair(tests, "Restore test environment cache", "Save test environment cache", "test-environment")
  assert_cache_pair(semantic, "Restore test environment cache", "Save test environment cache", "test-environment")
  assert_cache_pair(
    nightly,
    "Restore nightly test environment cache",
    "Save nightly test environment cache",
    "test-environment-nightly"
  )

  assert_repository_integrity_steps(tests, false)
  assert_repository_integrity_steps(semantic, false)
  assert_repository_integrity_steps(nightly, false)
  assert_repository_integrity_steps(refresh, true)
end

T["CI-CONTRACT-003 declares the exact stale workflow trigger, job, and reusable call"] = function()
  local workflow = read_file(config.root .. "/.github/workflows/stale.yml")
  local stale = workflow_job(workflow, "stale")
  local reusable_stale = "AstroNvim/.github/.github/workflows/stale.yml@" .. ACTIONS_SHA.astro_workflows .. " # v1"

  assert.equals('"Close stale issues and PRs"', assert(workflow:match "name: ([^\n]+)"))
  assert.same(as_set { "stale" }, as_set(extract_two_space_job_names(workflow)))
  assert.equals('schedule:\n  - cron: "30 1 * * *" # run at 0130 UTC', extract_trigger_block(workflow))
  assert.is_nil(extract_guard(stale))
  assert_exact_permissions(stale, "      issues: write\n      pull-requests: write")
  assert_exact_uses(stale, { reusable_stale })
  assert.is_nil(stale:find("secrets:", 1, true))
  assert.is_nil(stale:find("actions/checkout", 1, true))
  assert.is_nil(stale:find("run:", 1, true))
end

return T

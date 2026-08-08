local MiniTest = require "mini.test"
local helpers = require "unit_helpers"

local T = MiniTest.new_set()

local function sorted_termcode_calls(calls)
  table.sort(calls, function(left, right) return left[1] < right[1] end)
  return calls
end

local function with_health(mappings, normalized, callback)
  local calls = {}
  local termcode_calls = {}
  helpers.with_module("astrolsp.health", {
    loaded = { astrolsp = { config = { mappings = mappings } } },
    vim = {
      api = {
        nvim_replace_termcodes = function(lhs, from_part, do_lt, special)
          table.insert(termcode_calls, { lhs, from_part, do_lt, special })
          return normalized[lhs] or lhs
        end,
      },
      health = {
        start = function(message) table.insert(calls, { "start", message }) end,
        ok = function(message) table.insert(calls, { "ok", message }) end,
        warn = function(message, advice) table.insert(calls, { "warn", message, advice }) end,
      },
    },
  }, function(health)
    health.check()
    callback(calls, termcode_calls)
  end)
end

local function assert_conflict_calls(calls)
  assert.equals(2, #calls)
  assert.same({ "start", "Checking for conflicting mappings" }, calls[1])
  assert.equals("warn", calls[2][1])
end

T["HLTH-MAP-001 [empty] starts and succeeds without mappings"] = function()
  with_health({}, {}, function(calls, termcode_calls)
    assert.same({
      { "start", "Checking for conflicting mappings" },
      { "ok", "No conflicting mappings detected" },
    }, calls)
    assert.same({}, termcode_calls)
  end)
end

T["HLTH-MAP-001 [distinct] succeeds for independently normalized mappings"] = function()
  with_health(
    { n = { aa = { desc = "one" }, bb = { desc = "two" } } },
    { aa = "A", bb = "B" },
    function(calls, termcode_calls)
      assert.same({
        { "start", "Checking for conflicting mappings" },
        { "ok", "No conflicting mappings detected" },
      }, calls)
      assert.same({
        { "aa", true, true, true },
        { "bb", true, true, true },
      }, sorted_termcode_calls(termcode_calls))
    end
  )
end

T["HLTH-MAP-002 [normalized] reports equivalent mappings within one mode"] = function()
  with_health({ n = { ["<Esc>"] = "escape", ["<C-[>"] = "control escape" } }, {
    ["<Esc>"] = "escape",
    ["<C-[>"] = "escape",
  }, function(calls)
    assert_conflict_calls(calls)
    assert.matches("Conflicting mappings detected in mode `n`", calls[2][2], 1, true)
    assert.matches("<Esc>", calls[2][2], 1, true)
    assert.matches("<C-[>", calls[2][2], 1, true)
    assert.matches("escape", calls[2][2], 1, true)
    assert.matches("control escape", calls[2][2], 1, true)
  end)
end

T["HLTH-MAP-003 [desc-and-action] reports descriptions and positional actions without prose ordering"] = function()
  with_health({ n = { leader = { desc = "described action" }, space = { "positional action" } } }, {
    leader = "same",
    space = "same",
  }, function(calls)
    assert_conflict_calls(calls)
    local warning = calls[2]
    assert.matches("Conflicting mappings detected in mode `n`", warning[2], 1, true)
    assert.matches("leader", warning[2], 1, true)
    assert.matches("space", warning[2], 1, true)
    assert.matches("described action", warning[2], 1, true)
    assert.matches("positional action", warning[2], 1, true)
    assert.matches("normalize the left hand side", warning[3], 1, true)
    assert.matches("<Leader>", warning[3], 1, true)
    assert.matches("<LocalLeader>", warning[3], 1, true)
  end)
end

T["HLTH-MAP-003 [multiple-modes] reports facts from each conflicted mode without mode ordering"] = function()
  with_health({
    n = { north = "normal north", south = "normal south" },
    i = { insert_one = "insert one", insert_two = "insert two" },
  }, {
    north = "normal",
    south = "normal",
    insert_one = "insert",
    insert_two = "insert",
  }, function(calls)
    assert_conflict_calls(calls)
    local warning = calls[2]
    assert.matches("Conflicting mappings detected in mode `n`", warning[2], 1, true)
    assert.matches("Conflicting mappings detected in mode `i`", warning[2], 1, true)
    assert.matches("north", warning[2], 1, true)
    assert.matches("south", warning[2], 1, true)
    assert.matches("insert_one", warning[2], 1, true)
    assert.matches("insert_two", warning[2], 1, true)
  end)
end

T["HLTH-MAP-002 [false-entry] ignores disabled mappings without normalizing them"] = function()
  with_health({ n = { disabled = false, first = "first", second = "second" } }, {
    first = "same",
    second = "same",
  }, function(calls, termcode_calls)
    assert_conflict_calls(calls)
    assert.same({
      { "first", true, true, true },
      { "second", true, true, true },
    }, sorted_termcode_calls(termcode_calls))
    assert.not_matches("disabled", calls[2][2], 1, true)
  end)
end

T["HLTH-MAP-004 [independent-modes] does not compare normalized mappings across modes"] = function()
  with_health(
    { n = { normal = "normal action" }, i = { insert = "insert action" } },
    {
      normal = "same",
      insert = "same",
    },
    function(calls)
      assert.same({
        { "start", "Checking for conflicting mappings" },
        { "ok", "No conflicting mappings detected" },
      }, calls)
    end
  )
end

return T

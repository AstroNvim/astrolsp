local MiniTest = require "mini.test"
local helpers = require "unit_helpers"

local T = MiniTest.new_set()

local function with_file_operations(config, clients, callback, extra_vim)
  local applied, uri_calls = {}, {}
  local vim_replacements = {
    lsp = {
      get_clients = function() return clients end,
      util = {
        apply_workspace_edit = function(edit, encoding) table.insert(applied, { edit = edit, encoding = encoding }) end,
      },
    },
    uri_from_fname = function(path)
      table.insert(uri_calls, path)
      return "uri:" .. path
    end,
  }
  for name, value in pairs(extra_vim or {}) do
    vim_replacements[name] = value
  end
  helpers.with_module("astrolsp.file_operations", {
    loaded = { astrolsp = { config = { file_operations = config } } },
    vim = vim_replacements,
  }, function(file_operations) callback(file_operations, applied, uri_calls) end)
end

local function operation_filter(glob, matches, options, scheme)
  return {
    scheme = scheme,
    pattern = { glob = glob, matches = matches, options = options },
  }
end

local function capability(...) return { filters = { ... } } end

local function with_matcher(config, clients, matcher, callback)
  local glob_calls, match_calls = {}, {}
  with_file_operations(
    config,
    clients,
    function(file_operations, applied, uri_calls) callback(file_operations, applied, uri_calls, glob_calls, match_calls) end,
    {
      fn = {
        fnamemodify = function(path, modifier)
          assert.equals(":p", modifier)
          return path
        end,
        glob2regpat = function(glob)
          table.insert(glob_calls, glob)
          return "regex:" .. glob
        end,
        match = function(path, regex)
          table.insert(match_calls, { path = path, regex = regex, ignorecase = vim.o.ignorecase })
          return matcher(path, regex)
        end,
      },
    }
  )
end

local function with_ignorecase(value, callback)
  local previous_ignorecase = vim.o.ignorecase
  vim.o.ignorecase = value
  local ok, result = xpcall(callback, debug.traceback)
  vim.o.ignorecase = previous_ignorecase
  if not ok then error(result, 0) end
  return result
end

T["FO-NORM-001 normalizes create/delete paths and rename paths"] = function()
  local clients = {
    {
      server_capabilities = { workspace = { fileOperations = { didCreate = capability(operation_filter("**", nil)) } } },
      notify = function() end,
    },
    {
      server_capabilities = { workspace = { fileOperations = { didDelete = capability(operation_filter("**", nil)) } } },
      notify = function() end,
    },
    {
      server_capabilities = { workspace = { fileOperations = { didRename = capability(operation_filter("**", nil)) } } },
      notify = function() end,
    },
  }
  with_matcher(
    { operations = { didCreate = true, didDelete = true, didRename = true } },
    clients,
    function() return 0 end,
    function(file_operations, _, uri_calls)
      file_operations.didCreateFiles { path = "/tmp/typed.lua", kind = "file" }
      file_operations.didDeleteFiles { "/tmp/one.lua", { path = "/tmp/two.lua", kind = "file" } }
      file_operations.didRenameFiles {
        { from = "/tmp/old-one.lua", to = { path = "/tmp/new-one.lua", kind = "file" } },
        { from = { path = "/tmp/old-two.lua", kind = "file" }, to = "/tmp/new-two.lua" },
      }
      assert.same({
        "/tmp/typed.lua",
        "/tmp/one.lua",
        "/tmp/two.lua",
        "/tmp/old-one.lua",
        "/tmp/new-one.lua",
        "/tmp/old-two.lua",
        "/tmp/new-two.lua",
      }, uri_calls)
    end
  )
end

T["FO-PAYLOAD-001 builds exact create/delete and rename URI payloads"] = function()
  local create_calls, delete_calls, rename_calls = {}, {}, {}
  local clients = {
    {
      server_capabilities = { workspace = { fileOperations = { didCreate = capability(operation_filter("**", nil)) } } },
      notify = function(_, _, params) table.insert(create_calls, params) end,
    },
    {
      server_capabilities = { workspace = { fileOperations = { didDelete = capability(operation_filter("**", nil)) } } },
      notify = function(_, _, params) table.insert(delete_calls, params) end,
    },
    {
      server_capabilities = { workspace = { fileOperations = { didRename = capability(operation_filter("**", nil)) } } },
      notify = function(_, _, params) table.insert(rename_calls, params) end,
    },
  }
  with_matcher(
    { operations = { didCreate = true, didDelete = true, didRename = true } },
    clients,
    function() return 0 end,
    function(file_operations)
      file_operations.didCreateFiles "/tmp/create.lua"
      file_operations.didDeleteFiles "/tmp/delete.lua"
      file_operations.didRenameFiles { from = "/tmp/old.lua", to = "/tmp/new.lua" }
    end
  )
  assert.same({ { files = { { uri = "uri:/tmp/create.lua" } } } }, create_calls)
  assert.same({ { files = { { uri = "uri:/tmp/delete.lua" } } } }, delete_calls)
  assert.same({ { files = { { oldUri = "uri:/tmp/old.lua", newUri = "uri:/tmp/new.lua" } } } }, rename_calls)
end

T["FO-NOTIFY-001 sends exact did methods and payloads"] = function()
  local notifications = {}
  local client = {
    server_capabilities = {
      workspace = {
        fileOperations = {
          didCreate = capability(operation_filter("**", nil)),
          didDelete = capability(operation_filter("**", nil)),
          didRename = capability(operation_filter("**", nil)),
        },
      },
    },
    notify = function(_, method, params) table.insert(notifications, { method = method, params = params }) end,
  }
  with_matcher(
    { operations = { didCreate = true, didDelete = true, didRename = true } },
    { client },
    function() return 0 end,
    function(file_operations)
      file_operations.didCreateFiles "/tmp/create.lua"
      file_operations.didDeleteFiles "/tmp/delete.lua"
      file_operations.didRenameFiles { from = "/tmp/old.lua", to = "/tmp/new.lua" }
    end
  )
  assert.same({
    { method = "workspace/didCreateFiles", params = { files = { { uri = "uri:/tmp/create.lua" } } } },
    { method = "workspace/didDeleteFiles", params = { files = { { uri = "uri:/tmp/delete.lua" } } } },
    {
      method = "workspace/didRenameFiles",
      params = { files = { { oldUri = "uri:/tmp/old.lua", newUri = "uri:/tmp/new.lua" } } },
    },
  }, notifications)
end

T["FO-REQUEST-001 requests exact will methods with timeout and applies only returned edits"] = function()
  local create_requests, delete_requests, rename_requests = {}, {}, {}
  local clients = {
    {
      offset_encoding = "utf-8",
      server_capabilities = {
        workspace = { fileOperations = { willCreate = capability(operation_filter("**", nil)) } },
      },
      request_sync = function(_, method, params, timeout)
        table.insert(create_requests, { method = method, params = params, timeout = timeout })
        return { result = { marker = "create" } }
      end,
    },
    {
      offset_encoding = "utf-16",
      server_capabilities = {
        workspace = { fileOperations = { willDelete = capability(operation_filter("**", nil)) } },
      },
      request_sync = function(_, method, params, timeout)
        table.insert(delete_requests, { method = method, params = params, timeout = timeout })
        return { result = { marker = "delete" } }
      end,
    },
    {
      offset_encoding = "utf-32",
      server_capabilities = {
        workspace = { fileOperations = { willRename = capability(operation_filter("**", nil)) } },
      },
      request_sync = function(_, method, params, timeout)
        table.insert(rename_requests, { method = method, params = params, timeout = timeout })
        return { result = { marker = "rename" } }
      end,
    },
  }
  with_matcher(
    { timeout = 913, operations = { willCreate = true, willDelete = true, willRename = true } },
    clients,
    function() return 0 end,
    function(file_operations, applied, uri_calls)
      file_operations.willCreateFiles "/tmp/create.lua"
      file_operations.willDeleteFiles { path = "/tmp/delete.lua", kind = "file" }
      file_operations.willRenameFiles { from = "/tmp/old.lua", to = "/tmp/new.lua", kind = "file" }
      assert.same({ "/tmp/create.lua", "/tmp/delete.lua", "/tmp/old.lua", "/tmp/new.lua" }, uri_calls)
      assert.same({
        { edit = { marker = "create" }, encoding = "utf-8" },
        { edit = { marker = "delete" }, encoding = "utf-16" },
        { edit = { marker = "rename" }, encoding = "utf-32" },
      }, applied)
    end
  )
  assert.same({
    { method = "workspace/willCreateFiles", params = { files = { { uri = "uri:/tmp/create.lua" } } }, timeout = 913 },
  }, create_requests)
  assert.same({
    { method = "workspace/willDeleteFiles", params = { files = { { uri = "uri:/tmp/delete.lua" } } }, timeout = 913 },
  }, delete_requests)
  assert.same({
    {
      method = "workspace/willRenameFiles",
      params = { files = { { oldUri = "uri:/tmp/old.lua", newUri = "uri:/tmp/new.lua" } } },
      timeout = 913,
    },
  }, rename_requests)
end

T["FO-NORM-002 gives rename kind precedence to rename, source, then destination"] = function()
  local calls = {}
  local client = {
    server_capabilities = {
      workspace = { fileOperations = { didRename = capability(operation_filter("**", "folder")) } },
    },
    notify = function(_, method, params) table.insert(calls, { method = method, params = params }) end,
  }
  with_matcher(
    { operations = { didRename = true } },
    { client },
    function() return 0 end,
    function(file_operations)
      file_operations.didRenameFiles {
        {
          from = { path = "/tmp/explicit-old", kind = "file" },
          to = { path = "/tmp/explicit-new", kind = "file" },
          kind = "folder",
        },
        { from = { path = "/tmp/source-old", kind = "folder" }, to = { path = "/tmp/source-new", kind = "file" } },
        { from = { path = "/tmp/destination-old" }, to = { path = "/tmp/destination-new", kind = "folder" } },
        {
          from = { path = "/tmp/rejected-old", kind = "folder" },
          to = { path = "/tmp/rejected-new", kind = "folder" },
          kind = "file",
        },
      }
    end
  )
  assert.same({
    {
      method = "workspace/didRenameFiles",
      params = {
        files = {
          { oldUri = "uri:/tmp/explicit-old", newUri = "uri:/tmp/explicit-new" },
          { oldUri = "uri:/tmp/source-old", newUri = "uri:/tmp/source-new" },
          { oldUri = "uri:/tmp/destination-old", newUri = "uri:/tmp/destination-new" },
        },
      },
    },
  }, calls)
end

T["FO-FILTER-001 filters glob, kinds, schemes, and ignoreCase without changing ignorecase"] = function()
  local plain_calls, case_calls, non_file_calls, folder_calls = {}, {}, {}, {}
  local clients = {
    {
      server_capabilities = {
        workspace = { fileOperations = { didCreate = capability(operation_filter("**/plain.lua", "file")) } },
      },
      notify = function(_, method, params) table.insert(plain_calls, { method = method, params = params }) end,
    },
    {
      server_capabilities = {
        workspace = {
          fileOperations = {
            didCreate = capability(operation_filter("**/upper.lua", "file", { ignoreCase = true }, "FiLe")),
          },
        },
      },
      notify = function(_, method, params) table.insert(case_calls, { method = method, params = params }) end,
    },
    {
      server_capabilities = {
        workspace = { fileOperations = { didCreate = capability(operation_filter("**", nil, nil, "zip")) } },
      },
      notify = function(_, method, params) table.insert(non_file_calls, { method = method, params = params }) end,
    },
    {
      server_capabilities = {
        workspace = { fileOperations = { didCreate = capability(operation_filter("**/folder", "folder")) } },
      },
      notify = function(_, method, params) table.insert(folder_calls, { method = method, params = params }) end,
    },
  }
  with_ignorecase(true, function()
    with_matcher({ operations = { didCreate = true } }, clients, function(path, regex)
      if path == "/tmp/plain.lua" and regex == "regex:**/plain.lua" then return 0 end
      if path == "/tmp/UPPER.LUA" and regex == "\\cregex:**/upper.lua" then return 0 end
      if (path == "/tmp/folder" or path == "/tmp/trailing/") and regex == "regex:**/folder" then return 0 end
      return -1
    end, function(file_operations, _, _, glob_calls, match_calls)
      file_operations.didCreateFiles {
        "/tmp/plain.lua",
        "/tmp/UPPER.LUA",
        { path = "/tmp/folder", kind = "folder" },
        "/tmp/trailing/",
      }
      assert.equals(true, vim.o.ignorecase)
      assert.same(
        { "**/plain.lua", "**/plain.lua", "**/upper.lua", "**/upper.lua", "**/folder", "**/folder" },
        glob_calls
      )
      assert.same({
        { path = "/tmp/plain.lua", regex = "regex:**/plain.lua", ignorecase = false },
        { path = "/tmp/UPPER.LUA", regex = "regex:**/plain.lua", ignorecase = false },
        { path = "/tmp/plain.lua", regex = "\\cregex:**/upper.lua", ignorecase = false },
        { path = "/tmp/UPPER.LUA", regex = "\\cregex:**/upper.lua", ignorecase = false },
        { path = "/tmp/folder", regex = "regex:**/folder", ignorecase = false },
        { path = "/tmp/trailing/", regex = "regex:**/folder", ignorecase = false },
      }, match_calls)
    end)
  end)
  assert.same(
    { { method = "workspace/didCreateFiles", params = { files = { { uri = "uri:/tmp/plain.lua" } } } } },
    plain_calls
  )
  assert.same(
    { { method = "workspace/didCreateFiles", params = { files = { { uri = "uri:/tmp/UPPER.LUA" } } } } },
    case_calls
  )
  assert.same({}, non_file_calls)
  assert.same({
    {
      method = "workspace/didCreateFiles",
      params = { files = { { uri = "uri:/tmp/folder" }, { uri = "uri:/tmp/trailing/" } } },
    },
  }, folder_calls)
end

T["FO-CACHE-001 isolates paths, kinds, filter objects, and configurations"] = function()
  local folder_calls, path_calls, first_filter_calls, second_filter_calls, shared_calls = {}, {}, {}, {}, {}
  local folder_filter = operation_filter("**/folder", "folder")
  local path_filter = operation_filter("**/*.lua", "file")
  local first_filter = operation_filter("**/first.lua", "file")
  local second_filter = operation_filter("**/second.lua", "file")
  local shared_filter = operation_filter "**/shared"
  local shared_match_calls = 0
  local clients = {
    {
      server_capabilities = { workspace = { fileOperations = { didCreate = capability(folder_filter) } } },
      notify = function(_, method, params) table.insert(folder_calls, { method = method, params = params }) end,
    },
    {
      server_capabilities = { workspace = { fileOperations = { didCreate = capability(path_filter) } } },
      notify = function(_, method, params) table.insert(path_calls, { method = method, params = params }) end,
    },
    {
      server_capabilities = { workspace = { fileOperations = { didCreate = capability(first_filter) } } },
      notify = function(_, method, params) table.insert(first_filter_calls, { method = method, params = params }) end,
    },
    {
      server_capabilities = { workspace = { fileOperations = { didCreate = capability(second_filter) } } },
      notify = function(_, method, params) table.insert(second_filter_calls, { method = method, params = params }) end,
    },
    {
      server_capabilities = { workspace = { fileOperations = { didCreate = capability(shared_filter) } } },
      notify = function(_, method, params) table.insert(shared_calls, { method = method, params = params }) end,
    },
  }
  with_matcher({ operations = { didCreate = true } }, clients, function(path, regex)
    if regex == "regex:**/folder" then return path == "/tmp/a" and 0 or -1 end
    if regex == "regex:**/*.lua" then return path == "/tmp/yes.lua" and 0 or -1 end
    if regex == "regex:**/first.lua" then return -1 end
    if regex == "regex:**/second.lua" then return path == "/tmp/second.lua" and 0 or -1 end
    if path == "/tmp/shared" and regex == "regex:**/shared" then
      shared_match_calls = shared_match_calls + 1
      return 0
    end
    return -1
  end, function(file_operations)
    file_operations.didCreateFiles { path = "/tmp/a", kind = "folder" }
    file_operations.didCreateFiles "/tmp/afolder"
    file_operations.didCreateFiles { "/tmp/no.lua", "/tmp/yes.lua" }
    file_operations.didCreateFiles "/tmp/second.lua"
    file_operations.didCreateFiles { path = "/tmp/shared", kind = "file" }
    file_operations.didCreateFiles { path = "/tmp/shared", kind = "folder" }
    file_operations.didCreateFiles { path = "/tmp/shared", kind = "file" }
  end)
  assert.equals(2, shared_match_calls)
  assert.same(
    { { method = "workspace/didCreateFiles", params = { files = { { uri = "uri:/tmp/a" } } } } },
    folder_calls
  )
  assert.same(
    { { method = "workspace/didCreateFiles", params = { files = { { uri = "uri:/tmp/yes.lua" } } } } },
    path_calls
  )
  assert.same({}, first_filter_calls)
  assert.same(
    { { method = "workspace/didCreateFiles", params = { files = { { uri = "uri:/tmp/second.lua" } } } } },
    second_filter_calls
  )
  assert.same({
    { method = "workspace/didCreateFiles", params = { files = { { uri = "uri:/tmp/shared" } } } },
    { method = "workspace/didCreateFiles", params = { files = { { uri = "uri:/tmp/shared" } } } },
    { method = "workspace/didCreateFiles", params = { files = { { uri = "uri:/tmp/shared" } } } },
  }, shared_calls)
end

T["FO-CLIENT-001 evaluates matching filters independently for each client"] = function()
  local rejected_calls, accepted_calls = {}, {}
  local clients = {
    {
      server_capabilities = {
        workspace = { fileOperations = { didCreate = capability(operation_filter("**/skip.lua", "file")) } },
      },
      notify = function(_, method, params) table.insert(rejected_calls, { method = method, params = params }) end,
    },
    {
      server_capabilities = {
        workspace = { fileOperations = { didCreate = capability(operation_filter("**/keep.lua", "file")) } },
      },
      notify = function(_, method, params) table.insert(accepted_calls, { method = method, params = params }) end,
    },
  }
  with_matcher(
    { operations = { didCreate = true } },
    clients,
    function(path, regex) return path == "/tmp/keep.lua" and regex == "regex:**/keep.lua" and 0 or -1 end,
    function(file_operations) file_operations.didCreateFiles "/tmp/keep.lua" end
  )
  assert.same({}, rejected_calls)
  assert.same(
    { { method = "workspace/didCreateFiles", params = { files = { { uri = "uri:/tmp/keep.lua" } } } } },
    accepted_calls
  )
end

T["FO-POLICY-001 gates every method for disabled, absent, nil, and empty filters"] = function()
  local calls = 0
  local silent_client = {
    server_capabilities = { workspace = { fileOperations = {} } },
    notify = function() calls = calls + 1 end,
    request_sync = function() calls = calls + 1 end,
  }
  with_file_operations({ operations = {} }, { silent_client }, function(file_operations)
    file_operations.didCreateFiles "/tmp/file.lua"
    file_operations.didDeleteFiles "/tmp/file.lua"
    file_operations.didRenameFiles { from = "/tmp/old.lua", to = "/tmp/new.lua" }
    file_operations.willCreateFiles "/tmp/file.lua"
    file_operations.willDeleteFiles "/tmp/file.lua"
    file_operations.willRenameFiles { from = "/tmp/old.lua", to = "/tmp/new.lua" }
  end)
  with_file_operations({
    operations = {
      didCreate = true,
      didDelete = true,
      didRename = true,
      willCreate = true,
      willDelete = true,
      willRename = true,
    },
  }, { silent_client }, function(file_operations)
    file_operations.didCreateFiles "/tmp/file.lua"
    file_operations.didDeleteFiles "/tmp/file.lua"
    file_operations.didRenameFiles { from = "/tmp/old.lua", to = "/tmp/new.lua" }
    file_operations.willCreateFiles "/tmp/file.lua"
    file_operations.willDeleteFiles "/tmp/file.lua"
    file_operations.willRenameFiles { from = "/tmp/old.lua", to = "/tmp/new.lua" }
  end)
  local empty_filters_client = {
    server_capabilities = {
      workspace = {
        fileOperations = {
          didCreate = { filters = {} },
          didDelete = { filters = {} },
          didRename = { filters = {} },
          willCreate = { filters = {} },
          willDelete = { filters = {} },
          willRename = { filters = {} },
        },
      },
    },
    notify = function() calls = calls + 1 end,
    request_sync = function() calls = calls + 1 end,
  }
  with_file_operations({
    operations = {
      didCreate = true,
      didDelete = true,
      didRename = true,
      willCreate = true,
      willDelete = true,
      willRename = true,
    },
  }, { empty_filters_client }, function(file_operations)
    file_operations.didCreateFiles "/tmp/file.lua"
    file_operations.didDeleteFiles "/tmp/file.lua"
    file_operations.didRenameFiles { from = "/tmp/old.lua", to = "/tmp/new.lua" }
    file_operations.willCreateFiles "/tmp/file.lua"
    file_operations.willDeleteFiles "/tmp/file.lua"
    file_operations.willRenameFiles { from = "/tmp/old.lua", to = "/tmp/new.lua" }
  end)
  assert.equals(0, calls)
end

T["FO-PAYLOAD-002 makes no callbacks when all six non-empty filters reject"] = function()
  local callbacks = {}
  local rejecting_filter = capability(operation_filter("**/accepted.lua", "file"))
  local client = {
    server_capabilities = {
      workspace = {
        fileOperations = {
          didCreate = rejecting_filter,
          didDelete = rejecting_filter,
          didRename = rejecting_filter,
          willCreate = rejecting_filter,
          willDelete = rejecting_filter,
          willRename = rejecting_filter,
        },
      },
    },
    notify = function(_, method) table.insert(callbacks, method) end,
    request_sync = function(_, method) table.insert(callbacks, method) end,
  }
  with_matcher({
    operations = {
      didCreate = true,
      didDelete = true,
      didRename = true,
      willCreate = true,
      willDelete = true,
      willRename = true,
    },
  }, { client }, function() return -1 end, function(file_operations, applied, uri_calls)
    file_operations.didCreateFiles "/tmp/rejected.lua"
    file_operations.didDeleteFiles "/tmp/rejected.lua"
    file_operations.didRenameFiles { from = "/tmp/rejected.lua", to = "/tmp/renamed.lua" }
    file_operations.willCreateFiles "/tmp/rejected.lua"
    file_operations.willDeleteFiles "/tmp/rejected.lua"
    file_operations.willRenameFiles { from = "/tmp/rejected.lua", to = "/tmp/renamed.lua" }
    assert.same({}, applied)
    assert.same({}, uri_calls)
  end)
  assert.same({}, callbacks)
end

T["FO-ERROR-001 [response] does not apply edits for nil, error, or result-less responses"] = function()
  local requests = {}
  local clients = {
    {
      server_capabilities = {
        workspace = { fileOperations = { willCreate = capability(operation_filter("**", nil)) } },
      },
      request_sync = function(_, method) table.insert(requests, method) end,
    },
    {
      server_capabilities = {
        workspace = { fileOperations = { willDelete = capability(operation_filter("**", nil)) } },
      },
      request_sync = function(_, method)
        table.insert(requests, method)
        return { err = { message = "server error" } }
      end,
    },
    {
      server_capabilities = {
        workspace = { fileOperations = { willRename = capability(operation_filter("**", nil)) } },
      },
      request_sync = function(_, method)
        table.insert(requests, method)
        return {}
      end,
    },
  }
  with_matcher(
    { operations = { willCreate = true, willDelete = true, willRename = true } },
    clients,
    function() return 0 end,
    function(file_operations, applied)
      file_operations.willCreateFiles "/tmp/create.lua"
      file_operations.willDeleteFiles "/tmp/delete.lua"
      file_operations.willRenameFiles { from = "/tmp/old.lua", to = "/tmp/new.lua" }
      assert.same({}, applied)
    end
  )
  assert.same({ "workspace/willCreateFiles", "workspace/willDeleteFiles", "workspace/willRenameFiles" }, requests)
end

T["FO-ERROR-001 [request-callback] propagates exact request callback errors"] = function()
  local request_error = {}
  local client = {
    server_capabilities = {
      workspace = { fileOperations = { willCreate = capability(operation_filter("**", nil)) } },
    },
    request_sync = function() error(request_error, 0) end,
  }
  with_matcher(
    { operations = { willCreate = true } },
    { client },
    function() return 0 end,
    function(file_operations, applied)
      local ok, err = pcall(file_operations.willCreateFiles, "/tmp/request.lua")
      assert.is_false(ok)
      assert.is_true(rawequal(request_error, err))
      assert.same({}, applied)
    end
  )
end

T["FO-ERROR-001 [notification-callback] propagates exact notification callback errors"] = function()
  local notification_error = {}
  local client = {
    server_capabilities = {
      workspace = { fileOperations = { didCreate = capability(operation_filter("**", nil)) } },
    },
    notify = function() error(notification_error, 0) end,
  }
  with_matcher({ operations = { didCreate = true } }, { client }, function() return 0 end, function(file_operations)
    local ok, err = pcall(file_operations.didCreateFiles, "/tmp/notification.lua")
    assert.is_false(ok)
    assert.is_true(rawequal(notification_error, err))
  end)
end

T["FO-MALFORMED-001 [characterization] rejects non-path list entries"] = function()
  local client = {
    server_capabilities = { workspace = { fileOperations = { didCreate = capability(operation_filter("**", nil)) } } },
    notify = function() error "Malformed input must not notify" end,
  }
  with_file_operations({ operations = { didCreate = true } }, { client }, function(file_operations)
    local ok = pcall(file_operations.didCreateFiles, { 1 })
    assert(not ok, "Current malformed input behavior must remain characterized")
  end)
end

return T

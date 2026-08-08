local MiniTest = require "mini.test"
local config = require "config"
local environment = require "test_environment"

local T = MiniTest.new_set()

local function filesystem(entries)
  local time = 0
  entries = entries or {}
  return {
    lstat = function(path) return entries[path] end,
    mkdir = function(path)
      if entries[path] then return nil, "EEXIST" end
      entries[path] = { type = "directory" }
      return true
    end,
    rmdir = function(path)
      if not entries[path] then return nil, "ENOENT" end
      entries[path] = nil
      return true
    end,
    unlink = function(path)
      entries[path] = nil
      return true
    end,
    rename = function(from, to)
      if entries[to] then return nil, "EEXIST" end
      local moved, removed = {}, {}
      for path, entry in pairs(entries) do
        if path == from or path:sub(1, #from + 1) == from .. "/" then
          moved[to .. path:sub(#from + 1)] = entry
          table.insert(removed, path)
        end
      end
      for _, path in ipairs(removed) do
        entries[path] = nil
      end
      for path, entry in pairs(moved) do
        entries[path] = entry
      end
      return true
    end,
    scandir = function(path)
      local children = {}
      for child in pairs(entries) do
        local name = child:match("^" .. vim.pesc(path) .. "/([^/]+)$")
        if name then table.insert(children, name) end
      end
      return children
    end,
    now = function()
      time = time + 1
      return time
    end,
    wait = function() end,
  }
end

T["ENV-PATH-001 rejects unsafe relative lifecycle paths"] = function()
  assert.is_true(environment.is_safe_relative_path "data/nvim/lazy/mini.nvim")
  for _, path in ipairs { "", "/tmp/test", "../test", "a/../../b", "a//b", "a/", "C:/test", "a\\b" } do
    assert.is_false(environment.is_safe_relative_path(path))
  end
end

local function metadata_fixture()
  local commits = {
    ["lazy.nvim"] = string.rep("a", 40),
    ["mini.nvim"] = string.rep("b", 40),
    luassert = string.rep("c", 40),
    say = string.rep("d", 40),
  }
  local repositories = {}
  for name, expected in pairs(environment.repositories) do
    repositories[name] = {
      path = expected.path,
      commit = commits[name],
      tracked_clean = true,
      untracked = {},
    }
  end
  local dependencies = {
    ["mini.nvim"] = { path = repositories["mini.nvim"].path, commit = commits["mini.nvim"] },
    luassert = { path = repositories.luassert.path, commit = commits.luassert },
    say = { path = repositories.say.path, commit = commits.say },
  }
  local branches = { ["mini.nvim"] = "main", luassert = "master", say = "master" }
  local copies = {
    luassert = { path = "lua/luassert", checksums = { ["init.lua"] = "a" } },
    say = { path = "lua/say", checksums = { ["init.lua"] = "b" } },
  }
  local marker = {
    schema = environment.schema,
    specification_hash = environment.specification_hash,
    manifest = "manifest.json",
    fingerprint = "fingerprint.json",
    lockfile = "lazy-lock.json",
  }
  local manifest = {
    schema = environment.schema,
    specification_hash = environment.specification_hash,
    repositories = repositories,
    dependencies = dependencies,
    copies = copies,
  }
  local fingerprint = {
    schema = environment.schema,
    specification_hash = environment.specification_hash,
    repositories = vim.deepcopy(repositories),
    dependencies = { ["mini.nvim"] = commits["mini.nvim"], luassert = commits.luassert, say = commits.say },
    copies = { luassert = vim.deepcopy(copies.luassert.checksums), say = vim.deepcopy(copies.say.checksums) },
    lifecycle = {
      manifest = { size = 2, mtime = { sec = 2, nsec = 0 } },
      lock = { size = 3, mtime = { sec = 3, nsec = 0 } },
    },
  }
  local lock = {
    ["mini.nvim"] = { branch = branches["mini.nvim"], commit = commits["mini.nvim"] },
    luassert = { branch = branches.luassert, commit = commits.luassert },
    say = { branch = branches.say, commit = commits.say },
  }
  local lifecycle = {
    manifest = { sha256 = vim.fn.sha256(vim.json.encode(manifest)) },
    fingerprint = { sha256 = vim.fn.sha256(vim.json.encode(fingerprint)) },
    lock = { sha256 = vim.fn.sha256(vim.json.encode(lock)) },
  }
  marker.hashes = {
    manifest = lifecycle.manifest.sha256,
    fingerprint = lifecycle.fingerprint.sha256,
    lock = lifecycle.lock.sha256,
  }
  return marker, manifest, fingerprint, lock, lifecycle
end

local function update_lifecycle_hash(lifecycle, name, value)
  lifecycle[name] = { sha256 = vim.fn.sha256(vim.json.encode(value)) }
end

local function refresh_lifecycle_hash(marker, lifecycle, name, value)
  update_lifecycle_hash(lifecycle, name, value)
  marker.hashes[name] = lifecycle[name].sha256
end

T["ENV-VALIDATE-002 rejects metadata fields outside exact schemas"] = function()
  local marker, manifest, fingerprint, lock, lifecycle = metadata_fixture()
  manifest.extra = true
  refresh_lifecycle_hash(marker, lifecycle, "manifest", manifest)
  local valid, message = environment.validate_metadata(marker, manifest, fingerprint, lock, lifecycle)
  assert.is_false(valid)
  assert.matches("manifest schema", message)

  marker, manifest, fingerprint, lock, lifecycle = metadata_fixture()
  fingerprint.extra = true
  refresh_lifecycle_hash(marker, lifecycle, "fingerprint", fingerprint)
  valid, message = environment.validate_metadata(marker, manifest, fingerprint, lock, lifecycle)
  assert.is_false(valid)
  assert.matches("fingerprint schema", message)

  marker, manifest, fingerprint, lock, lifecycle = metadata_fixture()
  manifest.repositories["lazy.nvim"].extra = true
  refresh_lifecycle_hash(marker, lifecycle, "manifest", manifest)
  valid, message = environment.validate_metadata(marker, manifest, fingerprint, lock, lifecycle)
  assert.is_false(valid)
  assert.matches("lazy.nvim", message)

  marker, manifest, fingerprint, lock, lifecycle = metadata_fixture()
  fingerprint.repositories["lazy.nvim"].extra = true
  refresh_lifecycle_hash(marker, lifecycle, "fingerprint", fingerprint)
  valid, message = environment.validate_metadata(marker, manifest, fingerprint, lock, lifecycle)
  assert.is_false(valid)
  assert.matches("lazy.nvim", message)

  marker, manifest, fingerprint, lock, lifecycle = metadata_fixture()
  manifest.dependencies.say.extra = true
  refresh_lifecycle_hash(marker, lifecycle, "manifest", manifest)
  valid, message = environment.validate_metadata(marker, manifest, fingerprint, lock, lifecycle)
  assert.is_false(valid)
  assert.matches("say", message)

  marker, manifest, fingerprint, lock, lifecycle = metadata_fixture()
  manifest.copies.say.extra = true
  refresh_lifecycle_hash(marker, lifecycle, "manifest", manifest)
  valid, message = environment.validate_metadata(marker, manifest, fingerprint, lock, lifecycle)
  assert.is_false(valid)
  assert.matches("say", message)

  marker, manifest, fingerprint, lock, lifecycle = metadata_fixture()
  fingerprint.lifecycle.extra = true
  refresh_lifecycle_hash(marker, lifecycle, "fingerprint", fingerprint)
  valid, message = environment.validate_metadata(marker, manifest, fingerprint, lock, lifecycle)
  assert.is_false(valid)
  assert.matches("lifecycle", message)

  marker, manifest, fingerprint, lock, lifecycle = metadata_fixture()
  fingerprint.lifecycle.manifest.extra = true
  refresh_lifecycle_hash(marker, lifecycle, "fingerprint", fingerprint)
  valid, message = environment.validate_metadata(marker, manifest, fingerprint, lock, lifecycle)
  assert.is_false(valid)
  assert.matches("lifecycle", message)

  marker, manifest, fingerprint, lock, lifecycle = metadata_fixture()
  fingerprint.lifecycle.manifest.mtime.extra = true
  refresh_lifecycle_hash(marker, lifecycle, "fingerprint", fingerprint)
  valid, message = environment.validate_metadata(marker, manifest, fingerprint, lock, lifecycle)
  assert.is_false(valid)
  assert.matches("lifecycle", message)

  marker, manifest, fingerprint, lock, lifecycle = metadata_fixture()
  lock.say.extra = true
  refresh_lifecycle_hash(marker, lifecycle, "lock", lock)
  valid, message = environment.validate_metadata(marker, manifest, fingerprint, lock, lifecycle)
  assert.is_false(valid)
  assert.matches("lockfile", message)
end

T["ENV-VALIDATE-001 accepts full repository metadata and rejects unmanaged dependencies"] = function()
  local marker, manifest, fingerprint, lock, lifecycle = metadata_fixture()
  assert.is_true(environment.validate_metadata(marker, manifest, fingerprint, lock, lifecycle))
  assert.equals("lazy.nvim", manifest.repositories["lazy.nvim"].path)
  assert.equals(40, #manifest.repositories["lazy.nvim"].commit)
  lock.extra = { commit = string.rep("e", 40) }
  refresh_lifecycle_hash(marker, lifecycle, "lock", lock)
  local valid, message = environment.validate_metadata(marker, manifest, fingerprint, lock, lifecycle)
  assert.is_false(valid)
  assert.matches("unmanaged dependency", message)

  marker, manifest, fingerprint, lock, lifecycle = metadata_fixture()
  fingerprint.repositories.extra = vim.deepcopy(manifest.repositories["lazy.nvim"])
  refresh_lifecycle_hash(marker, lifecycle, "fingerprint", fingerprint)
  valid, message = environment.validate_metadata(marker, manifest, fingerprint, lock, lifecycle)
  assert.is_false(valid)
  assert.matches("unmanaged repository", message)

  marker, manifest, fingerprint, lock, lifecycle = metadata_fixture()
  fingerprint.dependencies.extra = string.rep("e", 40)
  refresh_lifecycle_hash(marker, lifecycle, "fingerprint", fingerprint)
  valid, message = environment.validate_metadata(marker, manifest, fingerprint, lock, lifecycle)
  assert.is_false(valid)
  assert.matches("unmanaged dependency", message)

  marker, manifest, fingerprint, lock, lifecycle = metadata_fixture()
  fingerprint.copies.extra = { ["init.lua"] = "e" }
  refresh_lifecycle_hash(marker, lifecycle, "fingerprint", fingerprint)
  valid, message = environment.validate_metadata(marker, manifest, fingerprint, lock, lifecycle)
  assert.is_false(valid)
  assert.matches("unmanaged copied library", message)
end

T["ENV-VALIDATE-001 rejects abbreviated commits, untracked files, and lifecycle metadata gaps"] = function()
  local marker, manifest, fingerprint, lock, lifecycle = metadata_fixture()
  manifest.repositories["lazy.nvim"].commit = "abcdef0"
  refresh_lifecycle_hash(marker, lifecycle, "manifest", manifest)
  local valid, message = environment.validate_metadata(marker, manifest, fingerprint, lock, lifecycle)
  assert.is_false(valid)
  assert.matches("lazy.nvim", message)

  marker, manifest, fingerprint, lock, lifecycle = metadata_fixture()
  manifest.repositories.say.untracked = { "generated.lua" }
  refresh_lifecycle_hash(marker, lifecycle, "manifest", manifest)
  valid, message = environment.validate_metadata(marker, manifest, fingerprint, lock, lifecycle)
  assert.is_false(valid)
  assert.matches("say", message)

  marker, manifest, fingerprint, lock, lifecycle = metadata_fixture()
  fingerprint.lifecycle.lock = nil
  refresh_lifecycle_hash(marker, lifecycle, "fingerprint", fingerprint)
  valid, message = environment.validate_metadata(marker, manifest, fingerprint, lock, lifecycle)
  assert.is_false(valid)
  assert.matches("lifecycle", message)
end

T["ENV-VALIDATE-001 rejects modified lifecycle files, copied libraries, and repositories"] = function()
  local marker, manifest, fingerprint, lock, lifecycle = metadata_fixture()
  marker.hashes.fingerprint = string.rep("0", 64)
  local valid, message = environment.validate_metadata(marker, manifest, fingerprint, lock, lifecycle)
  assert.is_false(valid)
  assert.matches("fingerprint", message)

  marker, manifest, fingerprint, lock, lifecycle = metadata_fixture()
  manifest.copies.luassert.checksums["init.lua"] = "changed"
  update_lifecycle_hash(lifecycle, "manifest", manifest)
  valid, message = environment.validate_metadata(marker, manifest, fingerprint, lock, lifecycle)
  assert.is_false(valid)
  assert.matches("manifest", message)

  marker, manifest, fingerprint, lock, lifecycle = metadata_fixture()
  fingerprint.dependencies.say = string.rep("e", 40)
  update_lifecycle_hash(lifecycle, "fingerprint", fingerprint)
  valid, message = environment.validate_metadata(marker, manifest, fingerprint, lock, lifecycle)
  assert.is_false(valid)
  assert.matches("fingerprint", message)

  marker, manifest, fingerprint, lock, lifecycle = metadata_fixture()
  lock.say.commit = string.rep("e", 40)
  update_lifecycle_hash(lifecycle, "lock", lock)
  valid, message = environment.validate_metadata(marker, manifest, fingerprint, lock, lifecycle)
  assert.is_false(valid)
  assert.matches("lock", message)

  marker, manifest, fingerprint, lock, lifecycle = metadata_fixture()
  manifest.copies.luassert.checksums["init.lua"] = "changed"
  refresh_lifecycle_hash(marker, lifecycle, "manifest", manifest)
  valid, message = environment.validate_metadata(marker, manifest, fingerprint, lock, lifecycle)
  assert.is_false(valid)
  assert.matches("copied library", message)

  marker, manifest, fingerprint, lock, lifecycle = metadata_fixture()
  manifest.repositories["lazy.nvim"].commit = string.rep("e", 40)
  refresh_lifecycle_hash(marker, lifecycle, "manifest", manifest)
  valid, message = environment.validate_metadata(marker, manifest, fingerprint, lock, lifecycle)
  assert.is_false(valid)
  assert.matches("lazy.nvim", message)
end

T["ENV-LOCK-001 releases after callback failures and reports release failures"] = function()
  local fs = filesystem()
  local ok, message = pcall(
    environment.with_lifecycle_lock,
    fs,
    "/repo/.tests.prepare.lock",
    function() error "callback failed" end
  )
  assert.is_false(ok)
  assert.matches("callback failed", message)
  assert.is_nil(fs.lstat "/repo/.tests.prepare.lock")

  local release_fs = filesystem()
  release_fs.rmdir = function() return nil, "EPERM" end
  local released, release_message = pcall(
    environment.with_lifecycle_lock,
    release_fs,
    "/repo/.tests.prepare.lock",
    function() error "callback failed" end
  )
  assert.is_false(released)
  assert.matches("callback failed", release_message)
  assert.matches("Failed to release", release_message)
end

T["ENV-LOCK-001 rejects unsafe locks and non-retryable acquisition errors"] = function()
  local lock_path = "/repo/.tests.prepare.lock"
  local linked = filesystem { [lock_path] = { type = "link" } }
  local linked_ok, linked_error = pcall(environment.with_lifecycle_lock, linked, lock_path, function() end)
  assert.is_false(linked_ok)
  assert.matches("symbolic link", linked_error)

  local blocked = filesystem()
  blocked.mkdir = function() return nil, "EACCES" end
  local blocked_ok, blocked_error = pcall(environment.with_lifecycle_lock, blocked, lock_path, function() end)
  assert.is_false(blocked_ok)
  assert.matches("EACCES", blocked_error)

  local contended_entries = { [lock_path] = { type = "directory" } }
  local contended = filesystem(contended_entries)
  local waits = 0
  contended.wait = function()
    waits = waits + 1
    contended_entries[lock_path] = nil
  end
  assert.equals("acquired", environment.with_lifecycle_lock(contended, lock_path, function() return "acquired" end))
  assert.equals(1, waits)
  assert.is_nil(contended.lstat(lock_path))

  local timed_out = filesystem { [lock_path] = { type = "directory" } }
  local timed_out_ok, timed_out_error = pcall(
    environment.with_lifecycle_lock,
    timed_out,
    lock_path,
    function() end,
    { timeout_ns = 0 }
  )
  assert.is_false(timed_out_ok)
  assert.matches("Timed out waiting", timed_out_error)
end

T["ENV-CLEAR-001 clears only the canonical tree and rejects symbolic links"] = function()
  local paths = environment.paths "/repo"
  local fs = filesystem {
    ["/repo"] = { type = "directory" },
    [paths.test_root] = { type = "directory" },
    [paths.test_root .. "/file"] = { type = "file" },
  }
  assert.is_true(environment.clear_test_environment(fs, "/repo", paths.test_root))
  assert.is_nil(fs.lstat(paths.test_root))
  local non_canonical, non_canonical_error = pcall(environment.clear_test_environment, fs, "/repo", "/tmp/other")
  assert.is_false(non_canonical)
  assert.matches("non%-canonical", non_canonical_error)
  local linked = filesystem { ["/repo"] = { type = "directory" }, [paths.test_root] = { type = "link" } }
  local safe, safe_error = pcall(environment.clear_test_environment, linked, "/repo", paths.test_root)
  assert.is_false(safe)
  assert.matches("symbolic%-link", safe_error)

  local nested_link = filesystem {
    ["/repo"] = { type = "directory" },
    [paths.test_root] = { type = "directory" },
    [paths.test_root .. "/escaped"] = { type = "link" },
  }
  safe, safe_error = pcall(environment.clear_test_environment, nested_link, "/repo", paths.test_root)
  assert.is_false(safe)
  assert.matches("symbolic%-link", safe_error)

  local root_link = filesystem { ["/repo"] = { type = "link" }, [paths.test_root] = { type = "directory" } }
  safe, safe_error = pcall(environment.clear_test_environment, root_link, "/repo", paths.test_root)
  assert.is_false(safe)
  assert.matches("symbolic%-link", safe_error)

  local removal_failure = filesystem {
    ["/repo"] = { type = "directory" },
    [paths.test_root] = { type = "directory" },
    [paths.test_root .. "/file"] = { type = "file" },
  }
  removal_failure.unlink = function(path)
    if path == paths.test_root .. "/file" then return nil, "EPERM" end
    return true
  end
  safe, safe_error = pcall(environment.clear_test_environment, removal_failure, "/repo", paths.test_root)
  assert.is_false(safe)
  assert.matches("Failed to clear test environment", safe_error)
  assert.matches("failed to remove .*/file: EPERM", safe_error)
  assert.equals("directory", removal_failure.lstat(paths.test_root).type)
  assert.equals("file", removal_failure.lstat(paths.test_root .. "/file").type)
  assert.is_nil(removal_failure.lstat(paths.lock_root))

  local removal_and_release_failure = filesystem {
    ["/repo"] = { type = "directory" },
    [paths.test_root] = { type = "directory" },
    [paths.test_root .. "/file"] = { type = "file" },
  }
  removal_and_release_failure.unlink = function(path)
    if path == paths.test_root .. "/file" then return nil, "EPERM" end
    return true
  end
  local rmdir = removal_and_release_failure.rmdir
  removal_and_release_failure.rmdir = function(path)
    if path == paths.lock_root then return nil, "EBUSY" end
    return rmdir(path)
  end
  safe, safe_error = pcall(environment.clear_test_environment, removal_and_release_failure, "/repo", paths.test_root)
  assert.is_false(safe)
  assert.matches("Failed to clear test environment", safe_error)
  assert.matches("failed to remove .*/file: EPERM", safe_error)
  assert.matches("Failed to release the test environment lock: EBUSY", safe_error)
  assert.equals("directory", removal_and_release_failure.lstat(paths.test_root).type)
  assert.equals("file", removal_and_release_failure.lstat(paths.test_root .. "/file").type)
  assert.equals("directory", removal_and_release_failure.lstat(paths.lock_root).type)
end

local function write_file(path, contents)
  local file = assert(io.open(path, "wb"))
  assert(file:write(contents))
  file:close()
end

local function read_file(path)
  local file = assert(io.open(path, "rb"))
  local contents = assert(file:read "*a")
  file:close()
  return contents
end

local function run_prepare(environment_variables)
  local command = { "env" }
  for name, value in pairs(environment_variables or {}) do
    table.insert(command, name .. "=" .. value)
  end
  vim.list_extend(command, { "nvim", "-l", config.root .. "/tests/bootstrap.lua" })
  return vim.system(command, { cwd = config.root, text = true }):wait()
end

local function native_filesystem()
  return {
    lstat = vim.uv.fs_lstat,
    rmdir = vim.uv.fs_rmdir,
    unlink = vim.uv.fs_unlink,
    scandir = function(path)
      local scanner, scan_error = vim.uv.fs_scandir(path)
      if not scanner then return nil, scan_error end
      local children = {}
      while true do
        local name = vim.uv.fs_scandir_next(scanner)
        if not name then break end
        table.insert(children, name)
      end
      return children
    end,
  }
end

local function copy_tree(source, destination)
  local entry = assert(vim.uv.fs_lstat(source))
  if entry.type == "link" then error("Refusing to copy a symbolic link: " .. source, 0) end
  if entry.type == "file" then
    local copied, copy_error = vim.uv.fs_copyfile(source, destination)
    if not copied then error("Failed to copy " .. source .. ": " .. tostring(copy_error), 0) end
    return
  end
  if entry.type ~= "directory" then error("Refusing to copy unsupported path: " .. source, 0) end
  local created, create_error = vim.uv.fs_mkdir(destination, 448)
  if not created then
    error("Failed to create disposable directory " .. destination .. ": " .. tostring(create_error), 0)
  end
  local scanner, scan_error = vim.uv.fs_scandir(source)
  if not scanner then error("Failed to scan " .. source .. ": " .. tostring(scan_error), 0) end
  while true do
    local name = vim.uv.fs_scandir_next(scanner)
    if not name then break end
    copy_tree(source .. "/" .. name, destination .. "/" .. name)
  end
end

local function refresh_disposable_lifecycle(paths)
  local function metadata(path)
    local entry = assert(vim.uv.fs_lstat(path))
    return { size = entry.size, mtime = { sec = entry.mtime.sec, nsec = entry.mtime.nsec } }
  end
  local function write_json(path, value)
    local temporary = path .. ".tmp." .. tostring(vim.uv.hrtime())
    write_file(temporary, vim.json.encode(value))
    assert(vim.uv.fs_rename(temporary, path))
  end

  local fingerprint = vim.json.decode(read_file(paths.fingerprint))
  fingerprint.lifecycle = { manifest = metadata(paths.manifest), lock = metadata(paths.lockfile) }
  write_json(paths.fingerprint, fingerprint)

  local marker = vim.json.decode(read_file(paths.ready))
  marker.hashes = {
    manifest = vim.fn.sha256(read_file(paths.manifest)),
    fingerprint = vim.fn.sha256(read_file(paths.fingerprint)),
    lock = vim.fn.sha256(read_file(paths.lockfile)),
  }
  write_json(paths.ready, marker)
end

local function with_disposable_environment(callback)
  local root = config.root .. "/.tests.disposable-" .. tostring(vim.uv.hrtime())
  local paths = environment.paths(root)
  assert(vim.uv.fs_mkdir(root, 448))
  local ok, result = xpcall(function()
    copy_tree(config.test_root, paths.test_root)
    refresh_disposable_lifecycle(paths)
    local valid, validation_error = config.validate_environment(paths.test_root)
    assert.is_true(valid, validation_error)
    return callback(paths)
  end, debug.traceback)
  local removed, cleanup_error = environment.remove_tree(native_filesystem(), root)
  if not removed then error("Failed to clean disposable test environment: " .. tostring(cleanup_error), 0) end
  if not ok then error(result, 0) end
end

local function assert_ordinary_marked_preparation_fails(paths, expected_error)
  local actions = {}
  local ok, message = pcall(environment.prepare_environment, {
    ci_recovery = false,
    classify = function() return "marked" end,
    validate_marked = function()
      table.insert(actions, "validate_marked")
      return config.validate_environment(paths.test_root)
    end,
    set_offline = function() table.insert(actions, "set_offline") end,
    remove_staging = function() table.insert(actions, "remove_staging") end,
    remove_environment = function() table.insert(actions, "remove_environment") end,
    create = function() table.insert(actions, "create") end,
    cleanup_staging = function() table.insert(actions, "cleanup_staging") end,
  })
  assert.is_false(ok)
  assert.matches(expected_error, message)
  assert.same({ "set_offline", "validate_marked" }, actions)
end

local function lifecycle_evidence()
  local evidence = {}
  for name, path in pairs {
    ready = config.ready,
    manifest = config.manifest,
    fingerprint = config.fingerprint,
    lock = config.lockfile,
  } do
    local entry = assert(vim.uv.fs_lstat(path))
    evidence[name] = {
      contents = read_file(path),
      size = entry.size,
      mtime = { sec = entry.mtime.sec, nsec = entry.mtime.nsec },
    }
  end
  return evidence
end

local function owned_entries(root)
  local paths = environment.paths(root)
  local entries = {
    [root] = { type = "directory" },
    [paths.test_root] = { type = "directory" },
    [paths.ready] = { type = "file" },
    [paths.manifest] = { type = "file" },
    [paths.fingerprint] = { type = "file" },
    [paths.lockfile] = { type = "file" },
    [paths.lazy_path] = { type = "directory" },
    [paths.test_root .. "/data"] = { type = "directory" },
    [paths.test_root .. "/data/nvim"] = { type = "directory" },
    [paths.plugin_root] = { type = "directory" },
    [paths.lua_root] = { type = "directory" },
    [paths.state_root] = { type = "directory" },
    [paths.cache_root] = { type = "directory" },
    [paths.runtime_root] = { type = "directory" },
    [paths.state_root .. "/arbitrary-session"] = { type = "file" },
  }
  for name in pairs(environment.dependencies) do
    entries[paths.plugin_root .. "/" .. name] = { type = "directory" }
  end
  for _, name in ipairs(environment.copied_libraries) do
    entries[paths.lua_root .. "/" .. name] = { type = "directory" }
  end
  return paths, entries
end

T["ENV-PUBLISH-001 publishes only a validated staging tree by rename"] = function()
  local paths = environment.paths "/repo"
  local fs = filesystem {
    ["/repo"] = { type = "directory" },
    [paths.staging_root] = { type = "directory" },
    [paths.staging_root .. "/manifest.json"] = { type = "file" },
  }
  local validated = false
  local published, publish_error = environment.publish_staged_environment(fs, paths, function(path)
    validated = path == paths.staging_root
    return validated
  end)
  assert.is_true(published, publish_error)
  assert.is_true(validated)
  assert.is_nil(fs.lstat(paths.staging_root))
  assert.equals("directory", fs.lstat(paths.test_root).type)
  assert.equals("file", fs.lstat(paths.test_root .. "/manifest.json").type)

  local existing = filesystem {
    ["/repo"] = { type = "directory" },
    [paths.staging_root] = { type = "directory" },
    [paths.test_root] = { type = "directory" },
  }
  published, publish_error = environment.publish_staged_environment(existing, paths, function() return true end)
  assert.is_false(published)
  assert.matches("already exists", publish_error)
  assert.equals("directory", existing.lstat(paths.staging_root).type)

  local validation_entries = {
    ["/repo"] = { type = "directory" },
    [paths.staging_root] = { type = "directory" },
    [paths.staging_root .. "/manifest.json"] = { type = "file" },
  }
  local failed_validation = filesystem(validation_entries)
  local before_validation = vim.deepcopy(validation_entries)
  published, publish_error = environment.publish_staged_environment(failed_validation, paths, function(path)
    assert.equals(paths.staging_root, path)
    return false, "invalid staged marker"
  end)
  assert.is_false(published)
  assert.matches("staged environment validation failed: invalid staged marker", publish_error)
  assert.same(before_validation, validation_entries)

  local rename_entries = {
    ["/repo"] = { type = "directory" },
    [paths.staging_root] = { type = "directory" },
    [paths.staging_root .. "/manifest.json"] = { type = "file" },
  }
  local rename_failure = filesystem(rename_entries)
  rename_failure.rename = function() return nil, "EXDEV" end
  local before_rename = vim.deepcopy(rename_entries)
  published, publish_error = environment.publish_staged_environment(rename_failure, paths, function(path)
    assert.equals(paths.staging_root, path)
    return true
  end)
  assert.is_false(published)
  assert.matches("failed to atomically publish the test environment: EXDEV", publish_error)
  assert.same(before_rename, rename_entries)
end

T["ENV-REUSE-001 ignores ambient recovery signals and reuses the marked environment offline"] = function()
  assert.equals(environment.specification_hash, vim.fn.sha256(environment.specification_json))
  local before = lifecycle_evidence()
  local result = run_prepare { LAZY_OFFLINE = "1", TEST_PREPARE_CI = "1", TEST_PREPARE_RECOVERY = "1" }
  assert.equals(0, result.code, result.stderr)
  assert.same(before, lifecycle_evidence())
end

T["ENV-COPY-001 rejects copied-library tampering in a disposable tree"] = function()
  with_disposable_environment(function(paths)
    local path = paths.lua_root .. "/luassert/assert.lua"
    local tampered = read_file(path) .. "\n-- tampered\n"
    write_file(path, tampered)
    local valid, validation_error = config.validate_environment(paths.test_root)
    assert.is_false(valid)
    assert.matches("copied library checksums changed", validation_error)
    assert_ordinary_marked_preparation_fails(paths, "copied library checksums changed")
    assert.equals(tampered, read_file(path))
  end)
end

T["ENV-REPOSITORY-001 rejects tracked managed-dependency modifications in a disposable tree"] = function()
  with_disposable_environment(function(paths)
    local path = paths.plugin_root .. "/mini.nvim/LICENSE"
    local tampered = read_file(path) .. "\nmodified by ENV-REPOSITORY-001\n"
    write_file(path, tampered)
    local valid, validation_error = config.validate_environment(paths.test_root)
    assert.is_false(valid)
    assert.matches("managed dependency mini.nvim repository has tracked modifications", validation_error)
    assert_ordinary_marked_preparation_fails(paths, "repository has tracked modifications")
    assert.equals(tampered, read_file(path))
  end)
end

T["ENV-INVALID-001 rejects ownership violations in a disposable tree without mutation"] = function()
  with_disposable_environment(function(paths)
    local path = paths.test_root .. "/unexpected-artifact"
    write_file(path, "must remain")
    local valid, validation_error = config.validate_environment(paths.test_root)
    assert.is_false(valid)
    assert.matches("unexpected top%-level artifact", validation_error)
    assert_ordinary_marked_preparation_fails(paths, "unexpected top%-level artifact")
    assert.equals("must remain", read_file(path))
  end)
end

T["ENV-OWNERSHIP-001 accepts documented writable roots and rejects unmanaged siblings"] = function()
  local paths, entries = owned_entries "/repo"
  local fs = filesystem(entries)
  assert.is_true(environment.validate_owned_structure(paths, fs))

  entries[paths.test_root .. "/unexpected"] = { type = "file" }
  local valid, validation_error = environment.validate_owned_structure(paths, fs)
  assert.is_false(valid)
  assert.matches("unexpected top%-level artifact", validation_error)
  entries[paths.test_root .. "/unexpected"] = nil

  entries[paths.plugin_root .. "/extra"] = { type = "directory" }
  valid, validation_error = environment.validate_owned_structure(paths, fs)
  assert.is_false(valid)
  assert.matches("unexpected dependency artifact", validation_error)
  entries[paths.plugin_root .. "/extra"] = nil

  entries[paths.lua_root .. "/extra"] = { type = "directory" }
  valid, validation_error = environment.validate_owned_structure(paths, fs)
  assert.is_false(valid)
  assert.matches("unexpected copied%-library artifact", validation_error)
end

local function recovery_harness(initial_state, validation, options)
  options = options or {}
  local state = initial_state
  local actions = {}
  local offline = false
  local tree_evidence = {
    ready = "ready evidence",
    manifest = "manifest evidence",
    fingerprint = "fingerprint evidence",
    lock = "lock evidence",
    managed_tree = "managed tree evidence",
  }
  local before = vim.deepcopy(tree_evidence)
  local callbacks = {
    ci_recovery = options.ci_recovery == true,
    classify = function() return state end,
    validate_marked = function()
      table.insert(actions, "validate_marked")
      return validation[1], validation[2], validation[3]
    end,
    set_offline = function()
      offline = true
      table.insert(actions, "set_offline")
    end,
    remove_staging = function()
      table.insert(actions, "remove_staging")
      state = options.after_staging_state or "missing"
      return true
    end,
    remove_environment = function()
      table.insert(actions, "remove_environment")
      state = "missing"
      return true
    end,
    create = function()
      table.insert(actions, "create")
      if options.create_error then error(options.create_error, 0) end
      state = "marked"
      return "created"
    end,
    cleanup_staging = function()
      table.insert(actions, "cleanup_staging")
      if options.cleanup_throw then error(options.cleanup_throw, 0) end
      if options.cleanup_error then return false, options.cleanup_error end
      return true
    end,
  }
  return {
    actions = actions,
    before = before,
    offline = function() return offline end,
    run = function() return environment.prepare_environment(callbacks) end,
    state = function() return state end,
    tree_evidence = tree_evidence,
  }
end

local function assert_no_repair(run, expected_error)
  local ok, message = pcall(run.run)
  assert.is_false(ok)
  assert.matches(expected_error, message)
  assert.same({}, run.actions)
end

T["ENV-RECOVERY-001: rejects staging and partial environments without CI recovery"] = function()
  local staging = recovery_harness("staging", { true })
  assert_no_repair(staging, "staging")

  local partial = recovery_harness("partial", { true })
  assert_no_repair(partial, "partial")
end

T["ENV-RECOVERY-001: reuses valid marked environments and preserves invalid evidence"] = function()
  local ordinary_marked = recovery_harness("marked", { false, "incompatible schema", true })
  local ordinary_marked_before = vim.deepcopy(ordinary_marked.tree_evidence)
  local ok, message = pcall(ordinary_marked.run)
  assert.is_false(ok)
  assert.matches("incompatible schema", message)
  assert.is_true(ordinary_marked.offline())
  assert.same({ "set_offline", "validate_marked" }, ordinary_marked.actions)
  assert.same(ordinary_marked_before, ordinary_marked.tree_evidence)

  local operational = recovery_harness(
    "marked",
    { false, "cannot inspect repository revision", false },
    { ci_recovery = true }
  )
  local operational_before = vim.deepcopy(operational.tree_evidence)
  ok, message = pcall(operational.run)
  assert.is_false(ok)
  assert.matches("cannot inspect repository revision", message)
  assert.same({ "set_offline", "validate_marked" }, operational.actions)
  assert.same(operational_before, operational.tree_evidence)

  local reuse = recovery_harness("marked", { true })
  assert.equals("reused", reuse.run())
  assert.is_true(reuse.offline())
  assert.same({ "set_offline", "validate_marked" }, reuse.actions)
  assert.same(reuse.before, reuse.tree_evidence)
end

T["ENV-RECOVERY-001: repairs recoverable CI states"] = function()
  local ci_staging = recovery_harness("staging", { true }, { ci_recovery = true })
  assert.equals("created", ci_staging.run())
  assert.same({ "remove_staging", "create" }, ci_staging.actions)
  assert.equals("marked", ci_staging.state())

  local ci_partial = recovery_harness("partial", { true }, { ci_recovery = true })
  assert.equals("created", ci_partial.run())
  assert.same({ "remove_environment", "create" }, ci_partial.actions)
  assert.equals("marked", ci_partial.state())

  local ci_incompatible = recovery_harness("marked", { false, "incompatible schema", true }, { ci_recovery = true })
  assert.equals("created", ci_incompatible.run())
  assert.same({ "set_offline", "validate_marked", "remove_environment", "create" }, ci_incompatible.actions)
  assert.equals("marked", ci_incompatible.state())

  local missing = recovery_harness("missing", { true })
  assert.equals("created", missing.run())
  assert.same({ "create" }, missing.actions)
end

T["ENV-RECOVERY-001: reports staging cleanup failures with primary failures"] = function()
  local primary_error = {}
  local successful_cleanup = recovery_harness("missing", { true }, { create_error = primary_error })
  local ok, message = pcall(successful_cleanup.run)
  assert.is_false(ok)
  assert.is_true(rawequal(primary_error, message))
  assert.same({ "create", "cleanup_staging" }, successful_cleanup.actions)

  primary_error = {}
  local thrown_cleanup_error = {}
  local thrown_cleanup = recovery_harness("missing", { true }, {
    create_error = primary_error,
    cleanup_throw = thrown_cleanup_error,
  })
  ok, message = pcall(thrown_cleanup.run)
  assert.is_false(ok)
  assert.is_true(rawequal(primary_error, message.primary_error))
  assert.is_true(rawequal(thrown_cleanup_error, message.cleanup_error))
  assert.matches("Failed staging cleanup", tostring(message))
  assert.same({ "create", "cleanup_staging" }, thrown_cleanup.actions)

  primary_error = setmetatable({}, { __tostring = function() return "false-return primary failure" end })
  local false_cleanup_error = setmetatable({}, { __tostring = function() return "false-return cleanup failure" end })
  local false_cleanup = recovery_harness("missing", { true }, {
    create_error = primary_error,
    cleanup_error = false_cleanup_error,
  })
  ok, message = pcall(false_cleanup.run)
  assert.is_false(ok)
  assert.is_true(rawequal(false_cleanup_error, message.cleanup_error))
  assert.is_true(rawequal(primary_error, message.primary_error))
  assert.matches("false%-return primary failure", tostring(message))
  assert.matches("Failed staging cleanup: false%-return cleanup failure", tostring(message))
  assert.same({ "create", "cleanup_staging" }, false_cleanup.actions)
end

return T

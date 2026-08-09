local M = {}

M.schema = 3
M.specification_json =
  [[{"copied_libraries":["luassert","say"],"dependencies":["echasnovski/mini.nvim","lunarmodules/luassert","Olivine-Labs/say"],"layout":".tests/lazy.nvim,data/nvim/lazy,lua,state,cache,runtime,lazy-lock.json,manifest.json,fingerprint.json,.ready","lifecycle":"ready-binds-manifest-fingerprint-lock-sha256;fingerprint-binds-manifest-lock-size-mtime","repositories":["lazy.nvim","mini.nvim","luassert","say"],"schema":3}]]
M.specification_hash = "32f43a398f072ed7c9ff34f65a381208df71923d700ce564bb4f15e8a681d37c"
M.dependencies = {
  ["mini.nvim"] = "echasnovski/mini.nvim",
  luassert = "lunarmodules/luassert",
  say = "Olivine-Labs/say",
}
M.copied_libraries = { "luassert", "say" }
M.repositories = {
  ["lazy.nvim"] = { path = "lazy.nvim", untracked_allowlist = {} },
  ["mini.nvim"] = { path = "data/nvim/lazy/mini.nvim", untracked_allowlist = {} },
  luassert = { path = "data/nvim/lazy/luassert", untracked_allowlist = {} },
  say = { path = "data/nvim/lazy/say", untracked_allowlist = {} },
}

local ci_recovery_enabled = false

function M.enable_ci_recovery() ci_recovery_enabled = true end

function M.is_ci_recovery_enabled() return ci_recovery_enabled end

local function entry_type(entry)
  if type(entry) == "string" then return entry end
  return type(entry) == "table" and entry.type or nil
end

local function is_commit(value) return type(value) == "string" and value:match "^[0-9a-f]+$" and #value == 40 end

local function is_sha256(value) return type(value) == "string" and value:match "^[0-9a-f]+$" and #value == 64 end

local function has_exact_keys(value, expected)
  if type(value) ~= "table" then return false end
  for key in pairs(value) do
    if expected[key] == nil then return false end
  end
  for key in pairs(expected) do
    if value[key] == nil then return false end
  end
  return true
end

local function valid_size_mtime(value)
  return has_exact_keys(value, { size = true, mtime = true })
    and type(value.size) == "number"
    and has_exact_keys(value.mtime, { sec = true, nsec = true })
    and type(value.mtime.sec) == "number"
    and type(value.mtime.nsec) == "number"
end

function M.paths(root)
  local test_root = root .. "/.tests"
  return {
    root = root,
    test_root = test_root,
    staging_root = root .. "/.tests.bootstrap",
    lock_root = root .. "/.tests.prepare.lock",
    lazy_path = test_root .. "/lazy.nvim",
    plugin_root = test_root .. "/data/nvim/lazy",
    lua_root = test_root .. "/lua",
    state_root = test_root .. "/state",
    cache_root = test_root .. "/cache",
    runtime_root = test_root .. "/runtime",
    lockfile = test_root .. "/lazy-lock.json",
    manifest = test_root .. "/manifest.json",
    fingerprint = test_root .. "/fingerprint.json",
    ready = test_root .. "/.ready",
  }
end

function M.is_safe_relative_path(path)
  if type(path) ~= "string" or path == "" or path:sub(1, 1) == "/" or path:find("\\", 1, true) then return false end
  if path:match "^[A-Za-z]:" or path:find("//", 1, true) or path:sub(-1) == "/" then return false end
  for segment in path:gmatch "[^/]+" do
    if segment == "." or segment == ".." then return false end
  end
  return true
end

function M.find_symlink_component(root, path, lstat)
  if type(root) ~= "string" or type(path) ~= "string" or type(lstat) ~= "function" then return path end
  if path ~= root and path:sub(1, #root + 1) ~= root .. "/" then return path end
  if entry_type(lstat(root)) == "link" then return root end
  local current = root
  for segment in path:sub(#root + 2):gmatch "[^/]+" do
    current = current .. "/" .. segment
    if entry_type(lstat(current)) == "link" then return current end
  end
end

function M.has_safe_type(root, path, expected, lstat)
  return M.find_symlink_component(root, path, lstat) == nil and entry_type(lstat(path)) == expected
end

local function validate_directory_children(paths, filesystem, path, expected, label)
  if not M.has_safe_type(paths.root, path, "directory", filesystem.lstat) then
    return false, "required directory is missing or unsafe: " .. path, true
  end
  local children, scan_error = filesystem.scandir(path)
  if not children then return false, "cannot scan managed directory " .. path .. ": " .. tostring(scan_error), false end
  local actual = {}
  for _, name in ipairs(children) do
    actual[name] = true
    if expected[name] == nil then return false, "unexpected " .. label .. " artifact: " .. path .. "/" .. name, true end
  end
  for name, expected_type in pairs(expected) do
    if not actual[name] then
      return false, "required " .. label .. " artifact is missing: " .. path .. "/" .. name, true
    end
    local child = path .. "/" .. name
    if not M.has_safe_type(paths.root, child, expected_type, filesystem.lstat) then
      return false, "required " .. label .. " artifact is unsafe: " .. child, true
    end
  end
  return true
end

function M.validate_owned_structure(paths, filesystem)
  if not M.has_safe_type(paths.root, paths.test_root, "directory", filesystem.lstat) then
    return false, "test environment root is missing or unsafe: " .. paths.test_root, true
  end

  local top_level = {
    [".ready"] = "file",
    ["lazy-lock.json"] = "file",
    ["manifest.json"] = "file",
    ["fingerprint.json"] = "file",
    ["lazy.nvim"] = "directory",
    data = "directory",
    lua = "directory",
    state = "directory",
    cache = "directory",
    runtime = "directory",
  }
  local valid, validation_error, recoverable =
    validate_directory_children(paths, filesystem, paths.test_root, top_level, "top-level")
  if not valid then return false, validation_error, recoverable end

  valid, validation_error, recoverable =
    validate_directory_children(paths, filesystem, paths.test_root .. "/data", { nvim = "directory" }, "data")
  if not valid then return false, validation_error, recoverable end
  valid, validation_error, recoverable =
    validate_directory_children(paths, filesystem, paths.test_root .. "/data/nvim", { lazy = "directory" }, "data/nvim")
  if not valid then return false, validation_error, recoverable end

  local dependencies = {}
  for name in pairs(M.dependencies) do
    dependencies[name] = "directory"
  end
  valid, validation_error, recoverable =
    validate_directory_children(paths, filesystem, paths.plugin_root, dependencies, "dependency")
  if not valid then return false, validation_error, recoverable end

  local copies = {}
  for _, name in ipairs(M.copied_libraries) do
    copies[name] = "directory"
  end
  return validate_directory_children(paths, filesystem, paths.lua_root, copies, "copied-library")
end

function M.classify(paths, lstat)
  if lstat(paths.staging_root) then return "staging" end
  if not lstat(paths.test_root) then return "missing" end
  if lstat(paths.ready) then return "marked" end
  return "partial"
end

function M.lock_error_is_retryable(error_message)
  return error_message == "EEXIST"
    or (
      type(error_message) == "string"
      and (error_message:match "^EEXIST" or error_message:find("already exists", 1, true))
    )
end

function M.with_lifecycle_lock(filesystem, lock_path, callback, options)
  options = options or {}
  local deadline = filesystem.now() + (options.timeout_ns or 30000000000)
  while true do
    local created, lock_error = filesystem.mkdir(lock_path)
    if created then break end
    if not M.lock_error_is_retryable(lock_error) then
      error("Failed to acquire the test environment lock: " .. tostring(lock_error), 0)
    end
    local lock = filesystem.lstat(lock_path)
    if entry_type(lock) == "link" then error("Test environment lock is a symbolic link: " .. lock_path, 0) end
    if lock and entry_type(lock) ~= "directory" then
      error("Test environment lock is not a directory: " .. lock_path, 0)
    end
    if filesystem.now() >= deadline then error("Timed out waiting for the test environment lock: " .. lock_path, 0) end
    filesystem.wait(options.retry_delay_ms or 25)
  end

  local ok, result = xpcall(callback, debug.traceback)
  local released, release_error = filesystem.rmdir(lock_path)
  if not released then
    local release_message = "Failed to release the test environment lock: " .. tostring(release_error)
    if ok then error(release_message, 0) end
    result = result .. "\n" .. release_message
  end
  if not ok then error(result, 0) end
  return result
end

function M.remove_tree(filesystem, path)
  local function scan_directory(current)
    local entry = filesystem.lstat(current)
    if entry_type(entry) == "link" then return nil, "refusing to remove a symbolic-link path: " .. current end
    if entry_type(entry) ~= "directory" then
      return nil, "refusing to recursively remove a non-directory path: " .. current
    end
    local children, scan_error = filesystem.scandir(current)
    if not children then return nil, "failed to scan " .. current .. ": " .. tostring(scan_error) end
    return children
  end

  local function inspect(current)
    if not filesystem.lstat(current) then return true, false end
    local children, scan_error = scan_directory(current)
    if not children then return false, scan_error end
    for _, name in ipairs(children) do
      local child = current .. "/" .. name
      local child_entry = filesystem.lstat(child)
      if entry_type(child_entry) == "link" then return false, "refusing to remove a symbolic-link path: " .. child end
      if entry_type(child_entry) == "directory" then
        local safe, message = inspect(child)
        if not safe then return false, message end
      elseif entry_type(child_entry) ~= "file" then
        return false, "refusing to remove an unsupported path: " .. child
      end
    end
    return true, true
  end

  local safe, exists_or_error = inspect(path)
  if not safe then return false, exists_or_error end
  if not exists_or_error then return true end

  local function remove(current)
    local children, scan_error = scan_directory(current)
    if not children then return false, scan_error end
    for _, name in ipairs(children) do
      local child = current .. "/" .. name
      local entry = filesystem.lstat(child)
      local removed, remove_error
      if entry_type(entry) == "directory" then
        removed, remove_error = remove(child)
      else
        removed, remove_error = filesystem.unlink(child)
      end
      if not removed then return false, "failed to remove " .. child .. ": " .. tostring(remove_error) end
    end
    return filesystem.rmdir(current)
  end

  return remove(path)
end

function M.publish_staged_environment(filesystem, paths, validate)
  if not M.has_safe_type(paths.root, paths.staging_root, "directory", filesystem.lstat) then
    return false, "staging environment is missing or unsafe: " .. paths.staging_root
  end
  if filesystem.lstat(paths.test_root) then return false, "test environment already exists: " .. paths.test_root end
  local valid, validation_error = validate(paths.staging_root)
  if not valid then return false, "staged environment validation failed: " .. tostring(validation_error) end
  local published, publish_error = filesystem.rename(paths.staging_root, paths.test_root)
  if not published then
    return false, "failed to atomically publish the test environment: " .. tostring(publish_error)
  end
  return true
end

function M.clear_test_environment(filesystem, root, target)
  local paths = M.paths(root)
  target = target or paths.test_root
  if target ~= paths.test_root then error("Refusing to clear a non-canonical test environment path: " .. target, 0) end
  if M.find_symlink_component(root, target, filesystem.lstat) then
    error("Refusing to clear a test environment with a symbolic-link component: " .. target, 0)
  end
  return M.with_lifecycle_lock(filesystem, paths.lock_root, function()
    local entry = filesystem.lstat(target)
    if not entry then return false end
    if entry_type(entry) ~= "directory" then
      error("Refusing to clear a non-directory test environment: " .. target, 0)
    end
    local removed, remove_error = M.remove_tree(filesystem, target)
    if not removed then error("Failed to clear test environment: " .. tostring(remove_error), 0) end
    return true
  end)
end

local function incompatible_environment_error(reason)
  return ("Test environment is incomplete or incompatible. Run `make test-clear` then retry: %s"):format(reason)
end

local staging_cleanup_error = {
  __tostring = function(error_value) return error_value.message end,
}

local function combined_staging_cleanup_error(primary_error, cleanup_error)
  return setmetatable({
    message = tostring(primary_error) .. "\nFailed staging cleanup: " .. tostring(cleanup_error),
    primary_error = primary_error,
    cleanup_error = cleanup_error,
  }, staging_cleanup_error)
end

local function create_with_staging_cleanup(callbacks)
  local ok, result = xpcall(callbacks.create, function(error_value) return error_value end)
  if ok then return result end

  local cleanup_ok, removed, cleanup_error = pcall(callbacks.cleanup_staging)
  if cleanup_ok and removed then error(result, 0) end
  error(combined_staging_cleanup_error(result, cleanup_ok and cleanup_error or removed), 0)
end

function M.prepare_environment(callbacks)
  local state = callbacks.classify()
  local ci_recovery = callbacks.ci_recovery == true

  if state == "staging" then
    if not ci_recovery then error(incompatible_environment_error(state), 0) end
    callbacks.remove_staging()
    state = callbacks.classify()
  end

  if state == "marked" then
    callbacks.set_offline()
    local valid, validation_error, recoverable = callbacks.validate_marked()
    if valid then return "reused" end
    if not ci_recovery then error(incompatible_environment_error(validation_error), 0) end
    if recoverable ~= true then error(validation_error, 0) end
    callbacks.remove_environment()
    return create_with_staging_cleanup(callbacks)
  end

  if state == "partial" then
    if not ci_recovery then error(incompatible_environment_error(state), 0) end
    callbacks.remove_environment()
    return create_with_staging_cleanup(callbacks)
  end

  if state == "missing" then return create_with_staging_cleanup(callbacks) end
  error(incompatible_environment_error(state), 0)
end

function M.validate_metadata(marker, manifest, fingerprint, lock, lifecycle)
  if type(marker) ~= "table" or marker.schema ~= M.schema or marker.specification_hash ~= M.specification_hash then
    return false, "the .ready marker schema or specification hash is incompatible"
  end
  if
    marker.manifest ~= "manifest.json"
    or marker.fingerprint ~= "fingerprint.json"
    or marker.lockfile ~= "lazy-lock.json"
  then
    return false, "the .ready marker references unexpected lifecycle files"
  end
  if type(marker.hashes) ~= "table" then return false, "the .ready marker lifecycle hashes are missing" end
  for _, name in ipairs { "manifest", "fingerprint", "lock" } do
    if not is_sha256(marker.hashes[name]) then return false, "the .ready marker lifecycle hash is invalid: " .. name end
    if
      type(lifecycle) ~= "table"
      or type(lifecycle[name]) ~= "table"
      or marker.hashes[name] ~= lifecycle[name].sha256
    then
      return false, "the .ready marker lifecycle hash changed: " .. name
    end
  end
  if
    type(manifest) ~= "table"
    or manifest.schema ~= M.schema
    or manifest.specification_hash ~= M.specification_hash
    or not has_exact_keys(manifest, {
      schema = true,
      specification_hash = true,
      repositories = true,
      dependencies = true,
      copies = true,
    })
  then
    return false, "the manifest schema or specification hash is incompatible"
  end
  if
    type(fingerprint) ~= "table"
    or fingerprint.schema ~= M.schema
    or fingerprint.specification_hash ~= M.specification_hash
    or not has_exact_keys(fingerprint, {
      schema = true,
      specification_hash = true,
      repositories = true,
      dependencies = true,
      copies = true,
      lifecycle = true,
    })
  then
    return false, "the fingerprint schema or specification hash is incompatible"
  end
  if
    type(lock) ~= "table"
    or type(manifest.repositories) ~= "table"
    or type(manifest.dependencies) ~= "table"
    or type(manifest.copies) ~= "table"
    or type(fingerprint.repositories) ~= "table"
    or type(fingerprint.dependencies) ~= "table"
    or type(fingerprint.copies) ~= "table"
    or type(fingerprint.lifecycle) ~= "table"
  then
    return false, "the manifest or generated lockfile is invalid"
  end
  for name, expected in pairs(M.repositories) do
    local repository = manifest.repositories[name]
    local fingerprint_repository = fingerprint.repositories[name]
    if
      type(repository) ~= "table"
      or not has_exact_keys(repository, { path = true, commit = true, tracked_clean = true, untracked = true })
      or repository.path ~= expected.path
      or not is_commit(repository.commit)
      or repository.tracked_clean ~= true
      or type(repository.untracked) ~= "table"
      or not vim.deep_equal(repository.untracked, expected.untracked_allowlist)
      or type(fingerprint_repository) ~= "table"
      or not has_exact_keys(
        fingerprint_repository,
        { path = true, commit = true, tracked_clean = true, untracked = true }
      )
      or not vim.deep_equal(fingerprint_repository, repository)
    then
      return false, "the managed repository is missing or invalid: " .. name
    end
  end
  for name in pairs(manifest.repositories) do
    if M.repositories[name] == nil then return false, "the manifest contains an unmanaged repository: " .. name end
  end
  for name in pairs(fingerprint.repositories) do
    if M.repositories[name] == nil then return false, "the fingerprint contains an unmanaged repository: " .. name end
  end
  for name in pairs(M.dependencies) do
    local dependency = manifest.dependencies[name]
    if
      type(dependency) ~= "table"
      or not has_exact_keys(dependency, { path = true, commit = true })
      or dependency.path ~= M.repositories[name].path
      or dependency.commit ~= manifest.repositories[name].commit
    then
      return false, "the managed dependency is missing or invalid: " .. name
    end
    if
      not has_exact_keys(lock[name], { branch = true, commit = true })
      or type(lock[name].branch) ~= "string"
      or not is_commit(lock[name].commit)
      or lock[name].commit ~= dependency.commit
    then
      return false, "the generated lockfile does not match " .. name
    end
    if fingerprint.dependencies == nil or fingerprint.dependencies[name] ~= dependency.commit then
      return false, "the fingerprint does not match " .. name
    end
  end
  for name in pairs(manifest.dependencies) do
    if M.dependencies[name] == nil then return false, "the manifest contains an unmanaged dependency: " .. name end
  end
  for name in pairs(fingerprint.dependencies) do
    if M.dependencies[name] == nil then return false, "the fingerprint contains an unmanaged dependency: " .. name end
  end
  for name in pairs(lock) do
    if M.dependencies[name] == nil then
      return false, "the generated lockfile contains an unmanaged dependency: " .. name
    end
  end
  for _, name in ipairs(M.copied_libraries) do
    local copy = manifest.copies[name]
    if
      type(copy) ~= "table"
      or not has_exact_keys(copy, { path = true, checksums = true })
      or copy.path ~= "lua/" .. name
      or not M.is_safe_relative_path(copy.path)
      or type(copy.checksums) ~= "table"
    then
      return false, "the copied library is missing or invalid: " .. name
    end
    if fingerprint.copies == nil or not vim.deep_equal(fingerprint.copies[name], copy.checksums) then
      return false, "the fingerprint does not match copied library: " .. name
    end
  end
  for name in pairs(manifest.copies) do
    if not vim.tbl_contains(M.copied_libraries, name) then
      return false, "the manifest contains an unmanaged copied library: " .. name
    end
  end
  for name in pairs(fingerprint.copies) do
    if not vim.tbl_contains(M.copied_libraries, name) then
      return false, "the fingerprint contains an unmanaged copied library: " .. name
    end
  end
  if
    not has_exact_keys(fingerprint.lifecycle, { manifest = true, lock = true })
    or not valid_size_mtime(fingerprint.lifecycle.manifest)
    or not valid_size_mtime(fingerprint.lifecycle.lock)
  then
    return false, "lock lifecycle metadata is missing"
  end
  return true
end

return M

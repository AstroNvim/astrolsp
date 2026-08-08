#!/usr/bin/env -S nvim -l

local tests_dir = vim.fs.dirname(debug.getinfo(1, "S").source:sub(2))
package.path = tests_dir .. "/?.lua;" .. package.path

local config = require "config"
local environment = require "test_environment"

local function filesystem()
  return {
    lstat = vim.uv.fs_lstat,
    mkdir = function(path) return vim.uv.fs_mkdir(path, 448) end,
    rmdir = vim.uv.fs_rmdir,
    unlink = vim.uv.fs_unlink,
    rename = vim.uv.fs_rename,
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
    now = vim.uv.hrtime,
    wait = vim.wait,
  }
end

local function paths_for_test_root(test_root)
  return {
    test_root = test_root,
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

local function ensure_directory(path)
  local entry = vim.uv.fs_lstat(path)
  if entry then
    if entry.type ~= "directory" then error("Refusing to use a non-directory path: " .. path, 0) end
    return
  end
  local created, create_error = vim.uv.fs_mkdir(path, 448)
  if not created then error("Failed to create directory " .. path .. ": " .. tostring(create_error), 0) end
end

local function ensure_parent(path) ensure_directory(vim.fs.dirname(path)) end

local function write_json(path, value)
  ensure_parent(path)
  local temporary = path .. ".tmp." .. tostring(vim.uv.hrtime())
  local file = assert(io.open(temporary, "wb"))
  assert(file:write(vim.json.encode(value)))
  file:close()
  if not vim.uv.fs_rename(temporary, path) then
    vim.uv.fs_unlink(temporary)
    error("Failed to atomically publish " .. path, 0)
  end
end

local function read_file(path)
  local file = assert(io.open(path, "rb"))
  local contents = assert(file:read "*a")
  file:close()
  return contents
end

local function file_metadata(path)
  local entry = assert(vim.uv.fs_lstat(path))
  return {
    sha256 = vim.fn.sha256(read_file(path)),
    size = entry.size,
    mtime = { sec = entry.mtime.sec, nsec = entry.mtime.nsec },
  }
end

local function size_mtime(metadata)
  return {
    size = metadata.size,
    mtime = metadata.mtime,
  }
end

local function copy_tree(source, destination)
  local source_entry = vim.uv.fs_lstat(source)
  if not source_entry or source_entry.type == "link" then error("Refusing to copy an unsafe path: " .. source, 0) end
  if source_entry.type == "file" then
    ensure_parent(destination)
    local copied, copy_error = vim.uv.fs_copyfile(source, destination)
    if not copied then error("Failed to copy " .. source .. ": " .. tostring(copy_error), 0) end
    return
  end
  if source_entry.type ~= "directory" then error("Refusing to copy unsupported path: " .. source, 0) end
  ensure_directory(destination)
  local scanner, scan_error = vim.uv.fs_scandir(source)
  if not scanner then error("Failed to scan " .. source .. ": " .. tostring(scan_error), 0) end
  while true do
    local name = vim.uv.fs_scandir_next(scanner)
    if not name then break end
    copy_tree(source .. "/" .. name, destination .. "/" .. name)
  end
end

local function tree_checksums(path, relative, checksums)
  local entry = assert(vim.uv.fs_lstat(path))
  if entry.type == "link" then error("Copied library contains a symbolic link: " .. path, 0) end
  if entry.type == "file" then
    checksums[relative] = vim.fn.sha256(read_file(path))
    return checksums
  end
  local scanner = assert(vim.uv.fs_scandir(path))
  while true do
    local name = vim.uv.fs_scandir_next(scanner)
    if not name then break end
    local child_relative = relative == "" and name or relative .. "/" .. name
    tree_checksums(path .. "/" .. name, child_relative, checksums)
  end
  return checksums
end

local function run(command)
  local result = vim.system(command, { text = true }):wait()
  if result.code ~= 0 then
    error(("Command failed (%d): %s\n%s"):format(result.code, table.concat(command, " "), result.stderr), 0)
  end
  return result
end

local function repository_metadata(path, expected_path)
  local revision = run { "env", "GIT_OPTIONAL_LOCKS=0", "git", "-C", path, "rev-parse", "HEAD" }
  local status =
    run { "env", "GIT_OPTIONAL_LOCKS=0", "git", "-C", path, "status", "--porcelain", "--untracked-files=no" }
  if status.stdout ~= "" then error("Managed dependency has tracked modifications: " .. path, 0) end
  local untracked =
    run { "env", "GIT_OPTIONAL_LOCKS=0", "git", "-C", path, "status", "--porcelain", "--untracked-files=all" }
  local files = {}
  for line in untracked.stdout:gmatch "[^\n]+" do
    if line:sub(1, 2) == "??" then table.insert(files, line:sub(4)) end
  end
  table.sort(files)
  return { path = expected_path, commit = vim.trim(revision.stdout), tracked_clean = true, untracked = files }
end

local function setup_lazy(paths)
  vim.o.loadplugins = true
  vim.env.LAZY = paths.lazy_path
  vim.opt.rtp:prepend(paths.lazy_path)
  require("lazy").setup {
    root = paths.plugin_root,
    lockfile = paths.lockfile,
    local_spec = false,
    spec = {
      { "echasnovski/mini.nvim", name = "mini.nvim" },
      { "lunarmodules/luassert", name = "luassert" },
      { "Olivine-Labs/say", name = "say" },
    },
    install = { missing = false },
    checker = { enabled = false },
    change_detection = { enabled = false },
    rocks = { enabled = false },
    git = { cooldown = 0 },
    performance = { cache = { enabled = false } },
  }
  require("lazy").sync { wait = true, show = false }
end

local function create_fresh_environment()
  local paths = paths_for_test_root(config.staging_root)
  local removed, remove_error = environment.remove_tree(filesystem(), paths.test_root)
  if not removed then error("Failed to remove stale staging environment: " .. tostring(remove_error), 0) end
  ensure_directory(paths.test_root)
  ensure_directory(paths.test_root .. "/data")
  ensure_directory(paths.test_root .. "/data/nvim")
  ensure_directory(paths.plugin_root)
  ensure_directory(paths.lua_root)
  ensure_directory(paths.state_root)
  ensure_directory(paths.cache_root)
  ensure_directory(paths.runtime_root)

  vim.env.LAZY_OFFLINE = nil
  run {
    "git",
    "clone",
    "--depth=1",
    "--filter=blob:none",
    "--branch=stable",
    "https://github.com/folke/lazy.nvim.git",
    paths.lazy_path,
  }
  setup_lazy(paths)

  local repositories, dependencies = {}, {}
  for name, expected in pairs(environment.repositories) do
    local repository = repository_metadata(paths.test_root .. "/" .. expected.path, expected.path)
    if not vim.deep_equal(repository.untracked, expected.untracked_allowlist) then
      error("Managed dependency has unexpected untracked files: " .. expected.path, 0)
    end
    repositories[name] = repository
    if environment.dependencies[name] then
      dependencies[name] = { path = repository.path, commit = repository.commit }
    end
  end
  local copies = {}
  local sources = {
    luassert = paths.plugin_root .. "/luassert/src",
    say = paths.plugin_root .. "/say/src/say",
  }
  for name, source in pairs(sources) do
    local relative_path = "lua/" .. name
    local destination = paths.test_root .. "/" .. relative_path
    copy_tree(source, destination)
    copies[name] = { path = relative_path, checksums = tree_checksums(destination, "", {}) }
  end

  local manifest = {
    schema = environment.schema,
    specification_hash = environment.specification_hash,
    repositories = repositories,
    dependencies = dependencies,
    copies = copies,
  }
  write_json(paths.manifest, manifest)
  local fingerprint_dependencies, fingerprint_copies = {}, {}
  for name, dependency in pairs(dependencies) do
    fingerprint_dependencies[name] = dependency.commit
  end
  for name, copy in pairs(copies) do
    fingerprint_copies[name] = copy.checksums
  end
  local fingerprint = {
    schema = environment.schema,
    specification_hash = environment.specification_hash,
    repositories = repositories,
    dependencies = fingerprint_dependencies,
    copies = fingerprint_copies,
    lifecycle = {
      manifest = size_mtime(file_metadata(paths.manifest)),
      lock = size_mtime(file_metadata(paths.lockfile)),
    },
  }
  write_json(paths.fingerprint, fingerprint)
  write_json(paths.ready, {
    schema = environment.schema,
    specification_hash = environment.specification_hash,
    manifest = "manifest.json",
    fingerprint = "fingerprint.json",
    lockfile = "lazy-lock.json",
    hashes = {
      manifest = file_metadata(paths.manifest).sha256,
      fingerprint = file_metadata(paths.fingerprint).sha256,
      lock = file_metadata(paths.lockfile).sha256,
    },
  })

  local valid, validation_error = config.validate_environment(paths.test_root)
  if not valid then error("Staged environment validation failed: " .. validation_error, 0) end
  local published, publish_error =
    environment.publish_staged_environment(filesystem(), config, config.validate_environment)
  if not published then error(publish_error, 0) end
end

environment.with_lifecycle_lock(filesystem(), config.lock_root, function()
  local fs = filesystem()
  local function remove(path, label)
    local removed, remove_error = environment.remove_tree(fs, path)
    if not removed then error("Failed to remove " .. label .. ": " .. tostring(remove_error), 0) end
    return true
  end

  environment.prepare_environment {
    ci_recovery = environment.is_ci_recovery_enabled(),
    classify = config.classify_environment,
    validate_marked = config.validate_ready_environment,
    set_offline = function() vim.env.LAZY_OFFLINE = "1" end,
    remove_staging = function() return remove(config.staging_root, "stale staging environment") end,
    remove_environment = function() return remove(config.test_root, "incompatible test environment") end,
    create = create_fresh_environment,
    cleanup_staging = function() return remove(config.staging_root, "staging environment") end,
  }
end)

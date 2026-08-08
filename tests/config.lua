local environment = require "test_environment"

local M = {}

local function normalize(path) return vim.fs.normalize(path):gsub("/$", "") end

local function canonical(path)
  local resolved = vim.uv.fs_realpath(path)
  if not resolved then error("Failed to resolve the repository root: " .. path, 0) end
  return normalize(resolved)
end

M.root = canonical(vim.fs.dirname(vim.fs.dirname(debug.getinfo(1, "S").source:sub(2))))
M.environment_schema = environment.schema
M.specification_hash = environment.specification_hash
for name, value in pairs(environment.paths(M.root)) do
  M[name] = value
end

local function lstat(path) return vim.uv.fs_lstat(path) end

local function scandir(path)
  local scanner, scan_error = vim.uv.fs_scandir(path)
  if not scanner then return nil, scan_error end
  local children = {}
  while true do
    local name = vim.uv.fs_scandir_next(scanner)
    if not name then break end
    table.insert(children, name)
  end
  return children
end

local filesystem = { lstat = lstat, scandir = scandir }

local function read_file(path)
  local file, open_error = io.open(path, "rb")
  if not file then return nil, open_error end
  local contents = file:read "*a"
  file:close()
  return contents
end

local function read_json(path)
  local contents, read_error = read_file(path)
  if not contents then return nil, read_error, false end
  local ok, value = pcall(vim.json.decode, contents)
  if not ok then return nil, value, true end
  return value
end

local function file_metadata(path)
  local contents, read_error = read_file(path)
  if not contents then return nil, read_error, false end
  local entry = lstat(path)
  if not entry or entry.type ~= "file" then return nil, "not a regular file", false end
  return {
    sha256 = vim.fn.sha256(contents),
    size = entry.size,
    mtime = { sec = entry.mtime.sec, nsec = entry.mtime.nsec },
  }
end

local function same_metadata(actual, expected)
  return type(actual) == "table"
    and type(expected) == "table"
    and actual.size == expected.size
    and vim.deep_equal(actual.mtime, expected.mtime)
end

local function tree_checksums(path, relative, checksums)
  local entry = lstat(path)
  if not entry then return nil, "missing copied-library path: " .. path, false end
  if entry.type == "link" then return nil, "unsafe copied-library path: " .. path, true end
  if entry.type == "file" then
    local contents, read_error = read_file(path)
    if not contents then return nil, read_error, false end
    checksums[relative] = vim.fn.sha256(contents)
    return checksums
  end
  if entry.type ~= "directory" then return nil, "unsupported copied-library path: " .. path, true end
  local scanner, scan_error = vim.uv.fs_scandir(path)
  if not scanner then return nil, scan_error, false end
  while true do
    local name = vim.uv.fs_scandir_next(scanner)
    if not name then break end
    local child_relative = relative == "" and name or relative .. "/" .. name
    local result, result_error, recoverable = tree_checksums(path .. "/" .. name, child_relative, checksums)
    if not result then return nil, result_error, recoverable end
  end
  return checksums
end

local function run_git(arguments)
  return vim.system(vim.list_extend({ "env", "GIT_OPTIONAL_LOCKS=0", "git" }, arguments), { text = true }):wait()
end

local function verify_repository(test_root, repository)
  if not environment.is_safe_relative_path(repository.path) then return false, "unsafe repository path", true end
  local path = test_root .. "/" .. repository.path
  if not environment.has_safe_type(M.root, path, "directory", lstat) then
    return false, "missing or unsafe repository", true
  end
  local revision = run_git { "-C", path, "rev-parse", "HEAD" }
  if revision.code ~= 0 then return false, "cannot inspect repository revision", false end
  if vim.trim(revision.stdout) ~= repository.commit then return false, "resolved commit changed", true end
  local status = run_git { "-C", path, "status", "--porcelain", "--untracked-files=no" }
  if status.code ~= 0 then return false, "cannot inspect repository status", false end
  if status.stdout ~= "" then return false, "repository has tracked modifications", true end
  local untracked = run_git { "-C", path, "status", "--porcelain", "--untracked-files=all" }
  if untracked.code ~= 0 then return false, "cannot inspect repository untracked files", false end
  local actual_untracked = {}
  for line in untracked.stdout:gmatch "[^\n]+" do
    if line:sub(1, 2) == "??" then table.insert(actual_untracked, line:sub(4)) end
  end
  table.sort(actual_untracked)
  if not vim.deep_equal(actual_untracked, repository.untracked) then
    return false, "repository has unexpected untracked files", true
  end
  return true
end

function M.classify_environment() return environment.classify(environment.paths(M.root), lstat) end

local function paths_for_test_root(test_root)
  return {
    root = M.root,
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

function M.validate_environment(test_root)
  local paths = paths_for_test_root(test_root or M.test_root)
  local owned, ownership_error, recoverable = environment.validate_owned_structure(paths, filesystem)
  if not owned then return false, ownership_error, recoverable end
  for _, path in ipairs { paths.ready, paths.manifest, paths.fingerprint, paths.lockfile } do
    if not environment.has_safe_type(M.root, path, "file", lstat) then
      return false, "required lifecycle file is missing or unsafe: " .. path, true
    end
  end

  local marker, marker_error, marker_recoverable = read_json(paths.ready)
  local manifest, manifest_error, manifest_recoverable = read_json(paths.manifest)
  local fingerprint, fingerprint_error, fingerprint_recoverable = read_json(paths.fingerprint)
  local lock, lock_error, lock_recoverable = read_json(paths.lockfile)
  if not marker then return false, "cannot read .ready: " .. tostring(marker_error), marker_recoverable end
  if not manifest then return false, "cannot read manifest.json: " .. tostring(manifest_error), manifest_recoverable end
  if not fingerprint then
    return false, "cannot read fingerprint.json: " .. tostring(fingerprint_error), fingerprint_recoverable
  end
  if not lock then return false, "cannot read lazy-lock.json: " .. tostring(lock_error), lock_recoverable end

  local lifecycle = {}
  for name, path in pairs { manifest = paths.manifest, fingerprint = paths.fingerprint, lock = paths.lockfile } do
    local metadata, metadata_error = file_metadata(path)
    if not metadata then
      return false, "cannot read lifecycle metadata: " .. name .. " " .. tostring(metadata_error), false
    end
    lifecycle[name] = metadata
  end
  local valid, validation_error = environment.validate_metadata(marker, manifest, fingerprint, lock, lifecycle)
  if not valid then return false, validation_error, true end
  for name, path in pairs { manifest = paths.manifest, lock = paths.lockfile } do
    local metadata, metadata_error = file_metadata(path)
    if not metadata or not same_metadata(metadata, fingerprint.lifecycle[name]) then
      return false, "lifecycle metadata changed: " .. name .. " " .. tostring(metadata_error or "mismatch"), true
    end
  end
  for name, repository in pairs(manifest.repositories) do
    local repository_ok, repository_error, repository_recoverable = verify_repository(paths.test_root, repository)
    if not repository_ok then
      return false, "managed dependency " .. name .. " " .. repository_error, repository_recoverable
    end
  end
  for name, copy in pairs(manifest.copies) do
    local path = paths.test_root .. "/" .. copy.path
    if not environment.has_safe_type(M.root, path, "directory", lstat) then
      return false, "copied library is missing or unsafe: " .. name, true
    end
    local checksums, checksum_error, checksums_recoverable = tree_checksums(path, "", {})
    if not checksums or not vim.deep_equal(checksums, copy.checksums) then
      return false,
        "copied library checksums changed: " .. name .. " " .. tostring(checksum_error or "mismatch"),
        checksums and true or checksums_recoverable
    end
  end
  return true
end

function M.validate_ready_environment() return M.validate_environment(M.test_root) end

function M.assert_ready_environment()
  local valid, message = M.validate_ready_environment()
  if not valid then
    error(("Test environment is incomplete or incompatible. Run `make test-clear` then retry: %s"):format(message), 0)
  end
end

M.file_metadata = file_metadata
M.tree_checksums = tree_checksums

return M

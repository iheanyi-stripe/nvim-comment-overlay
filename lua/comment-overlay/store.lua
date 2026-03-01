--- comment-overlay data store
--- Manages comment persistence and in-memory cache with JSON file backing.

local config = require("comment-overlay.config")

local M = {}

---@type Comment[]
local comments = {}

---@type string|nil
local project_root_cache = nil

---@type boolean
local loaded = false

--- Return current ISO 8601 timestamp.
---@return string
local function iso_now()
  return os.date("!%Y-%m-%dT%H:%M:%SZ")
end

--- Generate a unique comment ID from timestamp and random hex suffix.
---@return string
local function generate_id()
  return string.format("%s_%04x", os.date("%Y%m%d%H%M%S"), math.random(0, 0xFFFF))
end

--- Find project root by walking up from CWD looking for `.git` directory,
--- then falling back to a directory containing `.nvim-comments.json`,
--- then falling back to CWD itself. Result is cached.
---@return string
function M.get_project_root()
  if project_root_cache then
    return project_root_cache
  end

  local cwd = vim.fn.getcwd()
  local storage_cfg = config.options.storage or config.defaults.storage

  -- If user explicitly configured a path, use that.
  if storage_cfg.path then
    project_root_cache = storage_cfg.path
    return project_root_cache
  end

  -- Walk up from CWD looking for .git directory.
  local dir = cwd
  while true do
    if vim.fn.isdirectory(dir .. "/.git") == 1 then
      project_root_cache = dir
      return project_root_cache
    end
    local parent = vim.fn.fnamemodify(dir, ":h")
    if parent == dir then
      break
    end
    dir = parent
  end

  -- Fallback: walk up looking for existing .nvim-comments.json.
  local filename = storage_cfg.filename or ".nvim-comments.json"
  dir = cwd
  while true do
    if vim.fn.filereadable(dir .. "/" .. filename) == 1 then
      project_root_cache = dir
      return project_root_cache
    end
    local parent = vim.fn.fnamemodify(dir, ":h")
    if parent == dir then
      break
    end
    dir = parent
  end

  -- Final fallback: CWD.
  project_root_cache = cwd
  return project_root_cache
end

--- Get the full path to the JSON storage file.
---@return string
local function storage_path()
  local root = M.get_project_root()
  local storage_cfg = config.options.storage or config.defaults.storage
  local filename = storage_cfg.filename or ".nvim-comments.json"
  return root .. "/" .. filename
end

--- Convert an absolute path to a path relative to project root.
---@param absolute_path string
---@return string
function M.get_relative_path(absolute_path)
  local root = M.get_project_root()
  -- Normalize: ensure root ends without trailing slash for clean sub.
  local prefix = root:gsub("/$", "") .. "/"
  if absolute_path:sub(1, #prefix) == prefix then
    return absolute_path:sub(#prefix + 1)
  end
  -- Already relative or outside project root; return as-is.
  return absolute_path
end

--- Load comments from the JSON file on disk into memory.
--- Safe against missing or corrupt files (starts with empty list).
function M.load()
  local path = storage_path()
  if vim.fn.filereadable(path) ~= 1 then
    comments = {}
    loaded = true
    return
  end

  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok or #lines == 0 then
    comments = {}
    loaded = true
    return
  end

  local raw = table.concat(lines, "\n")
  local decode_ok, data = pcall(vim.fn.json_decode, raw)
  if not decode_ok or type(data) ~= "table" then
    vim.notify("[comment-overlay] corrupt JSON file, starting fresh", vim.log.levels.WARN)
    comments = {}
    loaded = true
    return
  end

  comments = data.comments or {}
  loaded = true
end

--- Simple JSON pretty-printer (2-space indent).
---@param str string compact JSON
---@return string formatted JSON
local function pretty_json(str)
  local indent = 0
  local result = {}
  local in_string = false
  local i = 1
  while i <= #str do
    local ch = str:sub(i, i)
    if ch == '"' and (i == 1 or str:sub(i - 1, i - 1) ~= "\\") then
      in_string = not in_string
      result[#result + 1] = ch
    elseif in_string then
      result[#result + 1] = ch
    elseif ch == "{" or ch == "[" then
      indent = indent + 1
      result[#result + 1] = ch .. "\n" .. string.rep("  ", indent)
    elseif ch == "}" or ch == "]" then
      indent = indent - 1
      result[#result + 1] = "\n" .. string.rep("  ", indent) .. ch
    elseif ch == "," then
      result[#result + 1] = ",\n" .. string.rep("  ", indent)
    elseif ch == ":" then
      result[#result + 1] = ": "
    elseif ch ~= " " and ch ~= "\n" and ch ~= "\r" and ch ~= "\t" then
      result[#result + 1] = ch
    end
    i = i + 1
  end
  return table.concat(result)
end

--- Persist all in-memory comments to the JSON file on disk.
--- Pretty-prints with 2-space indentation.
function M.save()
  local path = storage_path()
  local data = { comments = comments }
  local json = vim.fn.json_encode(data)
  local formatted = pretty_json(json)
  local lines = vim.split(formatted, "\n", { plain = true })

  local write_ok, err = pcall(vim.fn.writefile, lines, path)
  if not write_ok then
    vim.notify("[comment-overlay] failed to save: " .. tostring(err), vim.log.levels.ERROR)
  end
end

--- Ensure comments are loaded before any read/write operation.
local function ensure_loaded()
  if not loaded then
    M.load()
  end
end

--- Add a new comment.
---@param file string relative path from project root
---@param line_start number 1-indexed
---@param line_end number 1-indexed, inclusive
---@param body string
---@param author string|nil
---@return Comment
function M.add(file, line_start, line_end, body, author)
  ensure_loaded()
  local now = iso_now()
  ---@type Comment
  local comment = {
    id = generate_id(),
    file = file,
    line_start = line_start,
    line_end = line_end,
    body = body,
    author = author,
    created_at = now,
    updated_at = now,
    resolved = false,
  }
  table.insert(comments, comment)
  M.save()
  return comment
end

--- Get a comment by its ID.
---@param id string
---@return Comment|nil
function M.get(id)
  ensure_loaded()
  for _, c in ipairs(comments) do
    if c.id == id then
      return c
    end
  end
  return nil
end

--- Get all comments for a given file, sorted by line_start ascending.
---@param file string relative path
---@return Comment[]
function M.get_for_file(file)
  ensure_loaded()
  local result = {}
  for _, c in ipairs(comments) do
    if c.file == file then
      table.insert(result, c)
    end
  end
  table.sort(result, function(a, b)
    return a.line_start < b.line_start
  end)
  return result
end

--- Get all comments that span a given line (line_start <= line <= line_end).
---@param file string relative path
---@param line number 1-indexed
---@return Comment[]
function M.get_for_line(file, line)
  ensure_loaded()
  local result = {}
  for _, c in ipairs(comments) do
    if c.file == file and c.line_start <= line and line <= c.line_end then
      table.insert(result, c)
    end
  end
  return result
end

--- Update a comment's body text.
---@param id string
---@param body string
---@return Comment|nil updated comment, or nil if not found
function M.update(id, body)
  ensure_loaded()
  for _, c in ipairs(comments) do
    if c.id == id then
      c.body = body
      c.updated_at = iso_now()
      M.save()
      return c
    end
  end
  return nil
end

--- Delete a comment by ID.
---@param id string
---@return boolean true if deleted
function M.delete(id)
  ensure_loaded()
  for i, c in ipairs(comments) do
    if c.id == id then
      table.remove(comments, i)
      M.save()
      return true
    end
  end
  return false
end

--- Toggle the resolved status of a comment.
---@param id string
---@return Comment|nil updated comment, or nil if not found
function M.resolve(id)
  ensure_loaded()
  for _, c in ipairs(comments) do
    if c.id == id then
      c.resolved = not c.resolved
      c.updated_at = iso_now()
      M.save()
      return c
    end
  end
  return nil
end

--- Return all comments.
---@return Comment[]
function M.get_all()
  ensure_loaded()
  return comments
end

return M

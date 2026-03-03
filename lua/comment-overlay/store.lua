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

---@type number|nil
local last_loaded_mtime = nil

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

--- Return true when comment is a reply.
---@param comment Comment
---@return boolean
local function is_reply(comment)
  return comment.kind == "reply"
end

--- Return root thread id for a comment.
---@param comment Comment
---@return string
local function thread_id(comment)
  return comment.thread_id or comment.id
end

--- Ensure thread fields exist for legacy comments loaded from disk.
---@param comment Comment
local function normalize_comment(comment)
  if not comment.kind or comment.kind == "" then
    comment.kind = "comment"
  end
  if not comment.thread_id or comment.thread_id == "" then
    comment.thread_id = comment.id
  end
  if comment.kind == "reply" then
    if not comment.parent_id or comment.parent_id == "" then
      comment.parent_id = comment.thread_id
    end
  else
    comment.parent_id = nil
  end
end

--- Normalize all loaded comments.
local function normalize_comments()
  for _, c in ipairs(comments) do
    normalize_comment(c)
  end
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

--- Get storage file mtime or nil if file doesn't exist.
---@return number|nil
local function storage_mtime()
  local mtime = vim.fn.getftime(storage_path())
  if mtime < 0 then
    return nil
  end
  return mtime
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
---@param force? boolean
---@return boolean reloaded true if in-memory cache changed from disk read
function M.load(force)
  if loaded and not force then
    return false
  end

  local path = storage_path()
  if vim.fn.filereadable(path) ~= 1 then
    comments = {}
    loaded = true
    last_loaded_mtime = nil
    return true
  end

  local mtime = storage_mtime()
  if loaded and mtime == last_loaded_mtime then
    return false
  end

  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok or #lines == 0 then
    comments = {}
    loaded = true
    last_loaded_mtime = mtime
    return true
  end

  local raw = table.concat(lines, "\n")
  local decode_ok, data = pcall(vim.fn.json_decode, raw)
  if not decode_ok or type(data) ~= "table" then
    vim.notify("[comment-overlay] corrupt JSON file, starting fresh", vim.log.levels.WARN)
    comments = {}
    loaded = true
    last_loaded_mtime = mtime
    return true
  end

  comments = data.comments or {}
  normalize_comments()
  loaded = true
  last_loaded_mtime = mtime
  return true
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
    return
  end
  last_loaded_mtime = storage_mtime()
end

--- Ensure comments are loaded before any read/write operation.
local function ensure_loaded()
  if not loaded then
    M.load()
  end
end

--- Add a comment or reply.
---@param file string relative path from project root
---@param line_start number 1-indexed
---@param line_end number 1-indexed, inclusive
---@param body string
---@param author string|nil
---@param parent_id string|nil
---@return Comment
function M.add(file, line_start, line_end, body, author, parent_id)
  ensure_loaded()

  local now = iso_now()
  local kind = parent_id and "reply" or "comment"
  local parent = parent_id and M.get(parent_id) or nil

  if parent then
    file = parent.file
    line_start = parent.line_start
    line_end = parent.line_end
  else
    parent_id = nil
    kind = "comment"
  end

  local id = generate_id()
  local tid = parent and thread_id(parent) or id

  ---@type Comment
  local comment = {
    id = id,
    file = file,
    line_start = line_start,
    line_end = line_end,
    body = body,
    author = author,
    kind = kind,
    thread_id = tid,
    parent_id = parent_id,
    resolved_by = nil,
    resolved_at = nil,
    created_at = now,
    updated_at = now,
    resolved = false,
  }

  table.insert(comments, comment)
  M.save()
  return comment
end

--- Add a reply to an existing comment/thread item.
---@param parent_id string
---@param body string
---@param author string|nil
---@return Comment|nil
function M.add_reply(parent_id, body, author)
  ensure_loaded()
  local parent = M.get(parent_id)
  if not parent then
    return nil
  end
  return M.add(parent.file, parent.line_start, parent.line_end, body, author, parent.id)
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

--- Get all comments for a given file.
---@param file string relative path
---@param opts? { roots_only?: boolean, thread_id?: string }
---@return Comment[]
function M.get_for_file(file, opts)
  ensure_loaded()
  opts = opts or {}

  local result = {}
  for _, c in ipairs(comments) do
    if c.file == file then
      if opts.thread_id and thread_id(c) ~= opts.thread_id then
        goto continue
      end
      if opts.roots_only and is_reply(c) then
        goto continue
      end
      table.insert(result, c)
    end
    ::continue::
  end

  table.sort(result, function(a, b)
    if a.line_start ~= b.line_start then
      return a.line_start < b.line_start
    end
    if thread_id(a) ~= thread_id(b) then
      return thread_id(a) < thread_id(b)
    end
    if (a.created_at or "") ~= (b.created_at or "") then
      return (a.created_at or "") < (b.created_at or "")
    end
    return a.id < b.id
  end)

  return result
end

--- Get all comments that span a given line (line_start <= line <= line_end).
---@param file string relative path
---@param line number 1-indexed
---@param opts? { roots_only?: boolean }
---@return Comment[]
function M.get_for_line(file, line, opts)
  ensure_loaded()
  opts = opts or {}

  local result = {}
  for _, c in ipairs(comments) do
    if c.file == file and c.line_start <= line and line <= c.line_end then
      if opts.roots_only and is_reply(c) then
        goto continue
      end
      table.insert(result, c)
    end
    ::continue::
  end
  return result
end

--- Get all comments in a thread by thread id.
---@param tid string
---@return Comment[]
function M.get_thread(tid)
  ensure_loaded()
  local result = {}
  for _, c in ipairs(comments) do
    if thread_id(c) == tid then
      table.insert(result, c)
    end
  end
  table.sort(result, function(a, b)
    if (a.created_at or "") ~= (b.created_at or "") then
      return (a.created_at or "") < (b.created_at or "")
    end
    return a.id < b.id
  end)
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
--- Deleting a root comment deletes the whole thread.
---@param id string
---@return boolean true if deleted
function M.delete(id)
  ensure_loaded()
  local target = M.get(id)
  if not target then
    return false
  end

  if is_reply(target) then
    for i, c in ipairs(comments) do
      if c.id == id then
        table.remove(comments, i)
        M.save()
        return true
      end
    end
    return false
  end

  local tid = thread_id(target)
  for i = #comments, 1, -1 do
    if thread_id(comments[i]) == tid then
      table.remove(comments, i)
    end
  end
  M.save()
  return true
end

--- Toggle the resolved status of a comment.
---@param id string
---@param resolved_by string|nil
---@return Comment|nil updated comment, or nil if not found
function M.resolve(id, resolved_by)
  ensure_loaded()
  for _, c in ipairs(comments) do
    if c.id == id then
      c.resolved = not c.resolved
      if c.resolved then
        c.resolved_by = resolved_by
        c.resolved_at = iso_now()
      else
        c.resolved_by = nil
        c.resolved_at = nil
      end
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

--- Force reload comments from disk.
---@return boolean reloaded
function M.reload()
  loaded = false
  return M.load(true)
end

--- Reload comments only if the storage file changed on disk.
---@return boolean reloaded
function M.reload_if_changed()
  if not loaded then
    return M.load(true)
  end
  local mtime = storage_mtime()
  if mtime ~= last_loaded_mtime then
    return M.load(true)
  end
  return false
end

return M

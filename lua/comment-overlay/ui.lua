--- comment-overlay floating window UI
--- Handles add, edit, and preview floats for comments.

local config = require("comment-overlay.config")

local M = {}

--- Tracks the currently open float so we can clean up.
---@type { win: number|nil, buf: number|nil }
local current_float = { win = nil, buf = nil }

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

--- Compute centered float dimensions, capping at 80% of editor size.
---@param width number requested width
---@param height number requested height
---@return number col, number row, number w, number h
local function centered_geometry(width, height)
  local editor_w = vim.o.columns
  local editor_h = vim.o.lines - vim.o.cmdheight - 1 -- account for statusline
  local w = math.min(width, math.floor(editor_w * 0.8))
  local h = math.min(height, math.floor(editor_h * 0.8))
  local col = math.floor((editor_w - w) / 2)
  local row = math.floor((editor_h - h) / 2)
  return col, row, w, h
end

--- Create a scratch buffer with common settings.
---@param lines string[]|nil initial lines
---@param modifiable boolean
---@return number buf
local function make_scratch_buf(lines, modifiable)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "markdown"
  if lines and #lines > 0 then
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  end
  if not modifiable then
    vim.bo[buf].modifiable = false
  end
  return buf
end

--- Shared float-creation logic.
---@param opts { title: string, title_hl: string|nil, lines: string[]|nil, modifiable: boolean, width: number|nil, height: number|nil }
---@return { win: number, buf: number }
local function create_float(opts)
  -- Close any existing float first.
  M.close()

  local cfg = config.options.float
  local width = opts.width or cfg.width
  local height = opts.height or cfg.height
  local col, row, w, h = centered_geometry(width, height)

  local buf = make_scratch_buf(opts.lines, opts.modifiable)

  local title_hl = opts.title_hl or config.options.highlights.comment_title
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = w,
    height = h,
    col = col,
    row = row,
    style = "minimal",
    border = cfg.border,
    title = { { opts.title, title_hl } },
    title_pos = cfg.title_pos,
  })

  -- Padding: shift text 1 space right for readability.
  vim.wo[win].winhl = "Normal:Normal,FloatBorder:" .. config.options.highlights.comment_border
  vim.wo[win].signcolumn = "no"
  vim.wo[win].wrap = true
  vim.wo[win].linebreak = true

  -- Auto-close when focus leaves.
  local augroup = vim.api.nvim_create_augroup("CommentOverlayFloat", { clear = true })
  vim.api.nvim_create_autocmd("WinLeave", {
    group = augroup,
    buffer = buf,
    once = true,
    callback = function()
      M.close()
    end,
  })

  current_float = { win = win, buf = buf }
  return current_float
end

--- Set keymaps to close a float without saving.
---@param buf number
local function set_close_keymaps(buf)
  local close = function()
    M.close()
  end
  vim.keymap.set("n", "q", close, { buffer = buf, silent = true, nowait = true })
  vim.keymap.set("n", "<Esc>", close, { buffer = buf, silent = true, nowait = true })
end

--- Set keymaps for save + close inside an editable float.
---@param buf number
---@param on_save fun(body: string)
local function set_save_keymaps(buf, on_save)
  local save_and_close = function()
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local body = table.concat(lines, "\n")
    M.close()
    on_save(body)
  end
  vim.keymap.set("n", "<C-s>", save_and_close, { buffer = buf, silent = true, nowait = true })
  vim.keymap.set("n", "<CR>", save_and_close, { buffer = buf, silent = true, nowait = true })
end

--- Build a separator line that fills the float width.
---@param width number|nil
---@return string
local function separator(width)
  local w = width or config.options.float.width
  return string.rep("\u{2500}", w - 2) -- U+2500 BOX DRAWINGS LIGHT HORIZONTAL
end

--- Format a line range label.
---@param line_start number
---@param line_end number
---@return string
local function line_range_label(line_start, line_end)
  if line_start == line_end then
    return "Line " .. line_start
  end
  return "Lines " .. line_start .. "-" .. line_end
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

--- Open a floating window to add a new comment.
---@param line_start number 1-indexed
---@param line_end number 1-indexed, inclusive
---@param on_save fun(body: string) called with the comment body text
function M.open_add(line_start, line_end, on_save)
  local title = "  Add Comment  " .. line_range_label(line_start, line_end)
  local handle = create_float({
    title = title,
    modifiable = true,
  })

  set_close_keymaps(handle.buf)
  set_save_keymaps(handle.buf, on_save)

  -- Start in insert mode for immediate typing.
  vim.cmd("startinsert")
end

--- Open a floating window to edit an existing comment.
---@param comment Comment
---@param on_save fun(body: string) called with updated body text
function M.open_edit(comment, on_save)
  local title = "  Edit Comment  " .. line_range_label(comment.line_start, comment.line_end)
  local lines = vim.split(comment.body, "\n", { plain = true })

  local handle = create_float({
    title = title,
    lines = lines,
    modifiable = true,
  })

  set_close_keymaps(handle.buf)
  set_save_keymaps(handle.buf, on_save)

  -- Start in insert mode at end of existing text.
  vim.cmd("normal! G$")
  vim.cmd("startinsert!")
end

--- Open a read-only preview of an existing comment.
---@param comment Comment
function M.open_preview(comment)
  local resolved_tag = comment.resolved and " \u{2713} Resolved" or ""
  local title = "  Comment  " .. line_range_label(comment.line_start, comment.line_end) .. resolved_tag
  local title_hl = comment.resolved and "DiagnosticOk" or nil

  -- Build content lines: body + separator + metadata.
  local body_lines = vim.split(comment.body, "\n", { plain = true })
  local content = {}
  for _, line in ipairs(body_lines) do
    table.insert(content, " " .. line) -- 1-space left padding
  end
  table.insert(content, "")
  table.insert(content, " " .. separator())

  -- Metadata footer.
  local date = ""
  if comment.created_at then
    date = string.sub(comment.created_at, 1, 10) -- YYYY-MM-DD portion
  end
  local author = comment.author or ""
  local meta_parts = {}
  if date ~= "" then
    table.insert(meta_parts, "Created: " .. date)
  end
  if author ~= "" then
    table.insert(meta_parts, "Author: " .. author)
  end
  if comment.kind == "reply" then
    table.insert(meta_parts, "Type: Reply")
  end
  if comment.resolved and comment.resolved_by and comment.resolved_by ~= "" then
    table.insert(meta_parts, "Resolved by: " .. comment.resolved_by)
  end
  if comment.resolved and comment.resolved_at and comment.resolved_at ~= "" then
    table.insert(meta_parts, "Resolved at: " .. comment.resolved_at)
  end
  if #meta_parts > 0 then
    table.insert(content, " " .. table.concat(meta_parts, "  "))
  end

  -- Size the preview to fit content, with a minimum.
  local h = math.max(#content + 1, 5)
  local cfg = config.options.float
  h = math.min(h, cfg.height + 4) -- don't grow unbounded

  local handle = create_float({
    title = title,
    title_hl = title_hl,
    lines = content,
    modifiable = false,
    height = h,
  })

  set_close_keymaps(handle.buf)
end

--- Close the currently open comment float, if any.
function M.close()
  local win = current_float.win
  local buf = current_float.buf
  current_float = { win = nil, buf = nil }

  -- Clear the autocommand group to prevent stale callbacks.
  pcall(vim.api.nvim_create_augroup, "CommentOverlayFloat", { clear = true })

  if win and vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_win_close(win, true)
  end
  if buf and vim.api.nvim_buf_is_valid(buf) then
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
  end
end

return M

--- comment-overlay list panel
--- Side panel showing all comments for the current file with navigation.

local config = require("comment-overlay.config")

local M = {}

-- Panel state ---------------------------------------------------------------

local state = {
  buf = nil, ---@type number|nil
  win = nil, ---@type number|nil
  source_buf = nil, ---@type number|nil  buffer that was active when panel opened
  source_win = nil, ---@type number|nil  window that was active when panel opened
  line_to_comment = {}, ---@type table<number, string>  list-buf line -> comment id
  comment_header_lines = {}, ---@type number[]  list-buf lines that are comment headers
  autocmd_group = nil, ---@type number|nil
}

-- Helpers -------------------------------------------------------------------

---Lazy-load the store module so list.lua has no hard init-time dep.
---@return table
local function storage()
  return require("comment-overlay.store")
end

---Return the relative filepath for a buffer (matches Comment.file).
---Uses store.get_relative_path so paths match what's persisted.
---@param bufnr number
---@return string
local function buf_relpath(bufnr)
  local abs = vim.api.nvim_buf_get_name(bufnr)
  if abs == "" then
    return ""
  end
  return storage().get_relative_path(abs)
end

---Check whether a window handle is still valid and visible.
---@param win number|nil
---@return boolean
local function win_valid(win)
  return win ~= nil and vim.api.nvim_win_is_valid(win)
end

---Check whether the panel buffer is still alive.
---@return boolean
local function buf_valid()
  return state.buf ~= nil and vim.api.nvim_buf_is_valid(state.buf)
end

---Get comments for the source buffer, sorted by line_start ascending.
---@return Comment[]
local function get_comments()
  if not state.source_buf or not vim.api.nvim_buf_is_valid(state.source_buf) then
    return {}
  end
  local relpath = buf_relpath(state.source_buf)
  if relpath == "" then
    return {}
  end
  local store = storage()
  local all = store.get_for_file(relpath) or {}
  table.sort(all, function(a, b)
    return a.line_start < b.line_start
  end)
  return all
end

-- Highlight groups ----------------------------------------------------------

local ns = vim.api.nvim_create_namespace("comment_overlay_list")

local HL = {
  title = "CommentOverlayListTitle",
  separator = "CommentOverlayListSeparator",
  header_active = "CommentOverlayListHeaderActive",
  header_resolved = "CommentOverlayListHeaderResolved",
  body = "CommentOverlayListBody",
  body_resolved = "CommentOverlayListBodyResolved",
  footer = "CommentOverlayListFooter",
  line_nr = "CommentOverlayListLineNr",
}

local function ensure_highlights()
  local function def(name, opts)
    if vim.fn.hlexists(name) == 0 then
      vim.api.nvim_set_hl(0, name, opts)
    end
  end
  def(HL.title, { bold = true, link = "Title" })
  def(HL.separator, { link = "Comment" })
  def(HL.header_active, { bold = true, link = "Keyword" })
  def(HL.header_resolved, { bold = true, link = "DiagnosticOk" })
  def(HL.body, { link = "Normal" })
  def(HL.body_resolved, { link = "Comment" })
  def(HL.footer, { link = "Comment" })
  def(HL.line_nr, { bold = true, link = "Number" })
end

-- Rendering -----------------------------------------------------------------

local SEPARATOR_CHAR = "─"
local MAX_BODY_LINES = 3

---Build the lines and highlight data for the panel buffer.
---@param comments Comment[]
---@param width number
---@return string[] lines, {line:number,col_start:number,col_end:number,hl:string}[] highlights
local function build_content(comments, width)
  local lines = {}
  local hls = {}
  local line_map = {}
  local header_lines = {}

  local sep = string.rep(SEPARATOR_CHAR, width)

  -- Title
  local count = #comments
  local title = string.format(" 󰆉 Comments (%d)", count)
  lines[#lines + 1] = title
  hls[#hls + 1] = { line = #lines - 1, col_start = 0, col_end = #title, hl = HL.title }

  -- Top separator
  lines[#lines + 1] = sep
  hls[#hls + 1] = { line = #lines - 1, col_start = 0, col_end = #sep, hl = HL.separator }

  if count == 0 then
    lines[#lines + 1] = ""
    lines[#lines + 1] = "  No comments in this file."
    hls[#hls + 1] = { line = #lines - 1, col_start = 0, col_end = -1, hl = HL.body }
    lines[#lines + 1] = ""
  else
    for _, comment in ipairs(comments) do
      -- Blank line before each comment
      lines[#lines + 1] = ""

      -- Header: line range + status
      local range
      if comment.line_end and comment.line_end > comment.line_start then
        range = string.format("L:%d-%d", comment.line_start, comment.line_end)
      else
        range = string.format("L:%d", comment.line_start)
      end

      local status_icon, status_label, header_hl
      if comment.resolved then
        status_icon = "✓"
        status_label = "Resolved"
        header_hl = HL.header_resolved
      else
        status_icon = "●"
        status_label = "Active"
        header_hl = HL.header_active
      end

      local header = string.format(" %s  %s %s", range, status_icon, status_label)
      lines[#lines + 1] = header
      local hline = #lines - 1
      header_lines[#header_lines + 1] = #lines -- 1-indexed for cursor positioning

      -- Highlight the line number portion distinctly
      local range_end = 1 + #range
      hls[#hls + 1] = { line = hline, col_start = 1, col_end = range_end, hl = HL.line_nr }
      hls[#hls + 1] = { line = hline, col_start = range_end, col_end = #header, hl = header_hl }

      -- Map this line to the comment id
      line_map[#lines] = comment.id

      -- Body (truncated)
      local body_lines = vim.split(comment.body or "", "\n", { plain = true })
      local body_hl = comment.resolved and HL.body_resolved or HL.body
      local shown = 0
      for _, bline in ipairs(body_lines) do
        if shown >= MAX_BODY_LINES then
          lines[#lines + 1] = " ..."
          hls[#hls + 1] = { line = #lines - 1, col_start = 0, col_end = -1, hl = body_hl }
          line_map[#lines] = comment.id
          break
        end
        local text = " " .. bline
        lines[#lines + 1] = text
        hls[#hls + 1] = { line = #lines - 1, col_start = 0, col_end = -1, hl = body_hl }
        line_map[#lines] = comment.id
        shown = shown + 1
      end
    end
  end

  -- Bottom separator + footer
  lines[#lines + 1] = ""
  lines[#lines + 1] = sep
  hls[#hls + 1] = { line = #lines - 1, col_start = 0, col_end = #sep, hl = HL.separator }
  local footer = " q close  e edit  d delete  r resolve"
  lines[#lines + 1] = footer
  hls[#hls + 1] = { line = #lines - 1, col_start = 0, col_end = #footer, hl = HL.footer }

  return lines, hls, line_map, header_lines
end

---Render content into the panel buffer.
local function render()
  if not buf_valid() then
    return
  end

  local opts = config.options.list or config.defaults.list
  local width = opts.width or 40

  local comments = get_comments()
  local lines, hls, line_map, header_lines = build_content(comments, width)

  state.line_to_comment = line_map
  state.comment_header_lines = header_lines

  vim.bo[state.buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  vim.bo[state.buf].modifiable = false

  -- Apply highlights
  vim.api.nvim_buf_clear_namespace(state.buf, ns, 0, -1)
  for _, h in ipairs(hls) do
    local col_end = h.col_end
    if col_end == -1 then
      col_end = #lines[h.line + 1] or 0
    end
    vim.api.nvim_buf_add_highlight(state.buf, ns, h.hl, h.line, h.col_start, col_end)
  end
end

-- Comment-under-cursor helpers ----------------------------------------------

---Return the comment id at the current cursor line, or nil.
---@return string|nil
local function comment_at_cursor()
  if not win_valid(state.win) then
    return nil
  end
  local line = vim.api.nvim_win_get_cursor(state.win)[1] -- 1-indexed
  return state.line_to_comment[line]
end

---Return the full comment object at cursor, or nil.
---@return Comment|nil
local function comment_obj_at_cursor()
  local id = comment_at_cursor()
  if not id then
    return nil
  end
  local comments = get_comments()
  for _, c in ipairs(comments) do
    if c.id == id then
      return c
    end
  end
  return nil
end

-- Keymaps -------------------------------------------------------------------

local function jump_to_comment()
  local comment = comment_obj_at_cursor()
  if not comment then
    return
  end
  if win_valid(state.source_win) then
    vim.api.nvim_set_current_win(state.source_win)
    vim.api.nvim_win_set_cursor(state.source_win, { comment.line_start, 0 })
    vim.cmd("normal! zz")
  end
end

local function edit_comment()
  local comment = comment_obj_at_cursor()
  if not comment then
    return
  end
  -- Switch to source window then open edit float
  if win_valid(state.source_win) then
    vim.api.nvim_set_current_win(state.source_win)
  end
  -- Defer so the window switch completes before the float opens
  vim.schedule(function()
    local ok, overlay = pcall(require, "comment-overlay")
    if ok and overlay.edit_comment then
      overlay.edit_comment(comment.id)
    end
  end)
end

local function delete_comment()
  local comment = comment_obj_at_cursor()
  if not comment then
    return
  end
  local choice = vim.fn.confirm("Delete this comment?", "&Yes\n&No", 2)
  if choice ~= 1 then
    return
  end
  storage().delete(comment.id)
  M.refresh()
end

local function toggle_resolved()
  local comment = comment_obj_at_cursor()
  if not comment then
    return
  end
  storage().resolve(comment.id)
  M.refresh()
end

local function next_comment()
  if not win_valid(state.win) then
    return
  end
  local cur = vim.api.nvim_win_get_cursor(state.win)[1]
  for _, hline in ipairs(state.comment_header_lines) do
    if hline > cur then
      vim.api.nvim_win_set_cursor(state.win, { hline, 0 })
      return
    end
  end
  -- Wrap to first
  if #state.comment_header_lines > 0 then
    vim.api.nvim_win_set_cursor(state.win, { state.comment_header_lines[1], 0 })
  end
end

local function prev_comment()
  if not win_valid(state.win) then
    return
  end
  local cur = vim.api.nvim_win_get_cursor(state.win)[1]
  for i = #state.comment_header_lines, 1, -1 do
    if state.comment_header_lines[i] < cur then
      vim.api.nvim_win_set_cursor(state.win, { state.comment_header_lines[i], 0 })
      return
    end
  end
  -- Wrap to last
  if #state.comment_header_lines > 0 then
    vim.api.nvim_win_set_cursor(state.win, { state.comment_header_lines[#state.comment_header_lines], 0 })
  end
end

local function add_comment()
  if win_valid(state.source_win) then
    vim.api.nvim_set_current_win(state.source_win)
  end
  vim.schedule(function()
    local ok, overlay = pcall(require, "comment-overlay")
    if ok and overlay.add_comment then
      overlay.add_comment()
    end
  end)
end

local function setup_keymaps()
  if not buf_valid() then
    return
  end
  local buf = state.buf
  local map_opts = { buffer = buf, nowait = true, silent = true }

  vim.keymap.set("n", "<CR>", jump_to_comment, map_opts)
  vim.keymap.set("n", "o", jump_to_comment, map_opts)
  vim.keymap.set("n", "e", edit_comment, map_opts)
  vim.keymap.set("n", "d", delete_comment, map_opts)
  vim.keymap.set("n", "r", toggle_resolved, map_opts)
  vim.keymap.set("n", "q", M.close, map_opts)
  vim.keymap.set("n", "j", next_comment, map_opts)
  vim.keymap.set("n", "k", prev_comment, map_opts)
  vim.keymap.set("n", "a", add_comment, map_opts)
end

-- Autocmds ------------------------------------------------------------------

local function setup_autocmds()
  if state.autocmd_group then
    vim.api.nvim_del_augroup_by_id(state.autocmd_group)
  end
  state.autocmd_group = vim.api.nvim_create_augroup("CommentOverlayList", { clear = true })

  -- Refresh list when entering a different source buffer
  vim.api.nvim_create_autocmd("BufEnter", {
    group = state.autocmd_group,
    callback = function(args)
      if not win_valid(state.win) then
        return
      end
      -- Ignore entering the list buffer itself
      if args.buf == state.buf then
        return
      end
      -- Update source tracking to the newly entered buffer
      local ft = vim.bo[args.buf].filetype
      -- Ignore special buffers
      if ft == "comment-overlay-list" or vim.bo[args.buf].buftype ~= "" then
        return
      end
      state.source_buf = args.buf
      state.source_win = vim.api.nvim_get_current_win()
      M.refresh()
    end,
  })

  -- Close list panel if its window is somehow closed externally
  vim.api.nvim_create_autocmd("WinClosed", {
    group = state.autocmd_group,
    callback = function(args)
      if state.win and tostring(state.win) == args.match then
        M.close()
      end
    end,
  })
end

local function teardown_autocmds()
  if state.autocmd_group then
    vim.api.nvim_del_augroup_by_id(state.autocmd_group)
    state.autocmd_group = nil
  end
end

-- Public API ----------------------------------------------------------------

---Open the comment list panel.
function M.open()
  -- Already open
  if win_valid(state.win) and buf_valid() then
    vim.api.nvim_set_current_win(state.win)
    return
  end

  ensure_highlights()

  -- Remember the source context
  state.source_win = vim.api.nvim_get_current_win()
  state.source_buf = vim.api.nvim_get_current_buf()

  local opts = config.options.list or config.defaults.list
  local width = opts.width or 40
  local position = opts.position or "right"

  -- Create the split
  if position == "left" then
    vim.cmd("topleft vertical " .. width .. "split")
  elseif position == "bottom" then
    local height = opts.height or 15
    vim.cmd("botright " .. height .. "split")
  else
    -- Default: right
    vim.cmd("botright vertical " .. width .. "split")
  end

  state.win = vim.api.nvim_get_current_win()

  -- Create or reuse the panel buffer
  if not buf_valid() then
    state.buf = vim.api.nvim_create_buf(false, true)
    vim.bo[state.buf].buftype = "nofile"
    vim.bo[state.buf].bufhidden = "wipe"
    vim.bo[state.buf].swapfile = false
    vim.bo[state.buf].filetype = "comment-overlay-list"
    vim.api.nvim_buf_set_name(state.buf, "comment-overlay://list")
  end

  vim.api.nvim_win_set_buf(state.win, state.buf)

  -- Window options
  vim.wo[state.win].number = false
  vim.wo[state.win].relativenumber = false
  vim.wo[state.win].signcolumn = "no"
  vim.wo[state.win].wrap = true
  vim.wo[state.win].cursorline = true
  vim.wo[state.win].winfixwidth = true

  setup_keymaps()
  render()
  setup_autocmds()

  -- Move cursor to first comment header if available
  if #state.comment_header_lines > 0 then
    vim.api.nvim_win_set_cursor(state.win, { state.comment_header_lines[1], 0 })
  end

  -- Return focus to source window so the split doesn't steal focus unexpectedly
  -- (user can press <leader>cl again or click the panel)
  if win_valid(state.source_win) then
    vim.api.nvim_set_current_win(state.source_win)
  end
end

---Close the comment list panel.
function M.close()
  teardown_autocmds()

  if win_valid(state.win) then
    vim.api.nvim_win_close(state.win, true)
  end

  -- Buffer is bufhidden=wipe so it cleans itself up, but be safe
  if buf_valid() then
    pcall(vim.api.nvim_buf_delete, state.buf, { force = true })
  end

  state.win = nil
  state.buf = nil
  state.line_to_comment = {}
  state.comment_header_lines = {}
end

---Toggle the comment list panel.
function M.toggle()
  if win_valid(state.win) then
    M.close()
  else
    M.open()
  end
end

---Re-render the panel content. Call after add/edit/delete/resolve.
function M.refresh()
  if not win_valid(state.win) or not buf_valid() then
    return
  end
  local cursor_pos = vim.api.nvim_win_get_cursor(state.win)
  render()
  -- Restore cursor position, clamped to buffer length
  local line_count = vim.api.nvim_buf_line_count(state.buf)
  local row = math.min(cursor_pos[1], line_count)
  pcall(vim.api.nvim_win_set_cursor, state.win, { row, 0 })
end

---Return whether the panel is currently open.
---@return boolean
function M.is_open()
  return win_valid(state.win)
end

return M

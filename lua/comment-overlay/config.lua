--- comment-overlay configuration
--- All modules import defaults and user overrides from here.

local M = {}

---@class CommentOverlayConfig
---@field signs CommentOverlaySigns
---@field highlights CommentOverlayHighlights
---@field float CommentOverlayFloat
---@field list CommentOverlayList
---@field storage CommentOverlayStorage
---@field keymaps CommentOverlayKeymaps

---@class CommentOverlaySigns
---@field enabled boolean
---@field icon string
---@field hl string

---@class CommentOverlayHighlights
---@field comment_bg string  -- highlight group for commented line background
---@field comment_icon string  -- highlight group for sign column icon
---@field comment_virt string  -- highlight group for virtual text preview
---@field comment_border string  -- highlight group for floating window border
---@field comment_title string  -- highlight group for floating window title
---@field comment_count string  -- highlight group for comment count badge

---@class CommentOverlayFloat
---@field width number  -- percentage of editor width (0-1) or absolute columns
---@field height number
---@field border string|string[]  -- border style
---@field title_pos string

---@class CommentOverlayList
---@field position string  -- "right" | "left" | "bottom" | "float"
---@field width number  -- for left/right position
---@field height number  -- for bottom position
---@field auto_preview boolean

---@class CommentOverlayStorage
---@field path string|nil  -- nil = auto-detect project root
---@field filename string  -- default ".nvim-comments.json"

---@class CommentOverlayKeymaps
---@field add string
---@field delete string
---@field edit string
---@field next string
---@field prev string
---@field toggle_list string
---@field toggle_signs string

---@class Comment
---@field id string
---@field file string  -- relative path from project root
---@field line_start number  -- 1-indexed
---@field line_end number  -- 1-indexed, inclusive
---@field body string
---@field author string|nil
---@field created_at string  -- ISO 8601
---@field updated_at string  -- ISO 8601
---@field resolved boolean

M.namespace = "comment_overlay"

M.defaults = {
  signs = {
    enabled = true,
    icon = "󰆉",  -- nerd font comment icon
    hl = "CommentOverlaySign",
  },
  highlights = {
    comment_bg = "CommentOverlayBg",
    comment_icon = "CommentOverlaySign",
    comment_virt = "CommentOverlayVirt",
    comment_border = "CommentOverlayBorder",
    comment_title = "CommentOverlayTitle",
    comment_count = "CommentOverlayCount",
  },
  float = {
    width = 60,
    height = 10,
    border = "rounded",
    title_pos = "center",
  },
  list = {
    position = "right",
    width = 40,
    height = 15,
    auto_preview = true,
  },
  storage = {
    path = nil,  -- auto-detect
    filename = ".nvim-comments.json",
  },
  keymaps = {
    add = "<leader>ca",
    delete = "<leader>cd",
    edit = "<leader>ce",
    next = "]c",
    prev = "[c",
    toggle_list = "<leader>cl",
    toggle_signs = "<leader>cs",
  },
}

---@type CommentOverlayConfig
M.options = {}

function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", {}, M.defaults, opts or {})
end

return M

# nvim-comment-overlay

Google Docs-style inline comments for Neovim. Add comments to any line or selection, see them highlighted with visual cues, and browse them in a side panel.

Pure Lua. No dependencies. Requires Neovim 0.7+.

## Features

- **Line highlights** with warm amber background tint on commented lines
- **Sign column icons** (`󰆉`) on the gutter for quick scanning
- **Virtual text** previews at end-of-line showing truncated comment body
- **Floating windows** for adding, editing, and previewing comments
- **Side panel** listing all comments with status, navigation, and inline actions
- **Resolved/active** status tracking per comment
- **Dark and light** theme support (auto-detected)
- **Per-project storage** in `.nvim-comments.json` at project root

## Installation

### lazy.nvim

```lua
{
  "hqu/nvim-comment-overlay",
  event = "BufReadPost",
  config = function()
    require("comment-overlay").setup()
  end,
}
```

### Local (development)

```lua
{
  dir = "~/path/to/nvim-comment-overlay",
  event = "BufReadPost",
  config = function()
    require("comment-overlay").setup()
  end,
}
```

### Manual

```lua
vim.opt.runtimepath:prepend("~/path/to/nvim-comment-overlay")
require("comment-overlay").setup()
```

## Usage

### Adding a comment

1. Place cursor on a line and press `<leader>ca` to comment that line
2. Or select multiple lines in visual mode and press `<leader>ca`
3. A floating window opens — type your comment and press `<C-s>` or `<CR>` to save

### Viewing comments

- Commented lines show an amber background, a gutter icon, and a preview at end-of-line
- Multiple comments on the same line are separated by `│` in the virtual text
- Press `<leader>cl` to open the comment list panel

### Navigating comments

- `]c` and `[c` jump to the next/previous comment in the file
- The list panel lets you browse and jump to any comment

## Keymaps

### Global

| Key | Mode | Action |
|-----|------|--------|
| `<leader>ca` | normal | Add comment on current line |
| `<leader>ca` | visual | Add comment on selected lines |
| `<leader>ce` | normal | Edit comment under cursor |
| `<leader>cd` | normal | Delete comment under cursor |
| `<leader>cl` | normal | Toggle comment list panel |
| `<leader>cs` | normal | Toggle sign/highlight visibility |
| `]c` | normal | Jump to next comment |
| `[c` | normal | Jump to previous comment |

### Floating windows (add/edit)

| Key | Action |
|-----|--------|
| `<C-s>` | Save and close |
| `<CR>` | Save and close (normal mode) |
| `q` | Close without saving |
| `<Esc>` | Close without saving |

### List panel

| Key | Action |
|-----|--------|
| `<CR>` / `o` | Jump to comment location |
| `e` | Edit comment |
| `d` | Delete comment (with confirmation) |
| `r` | Toggle resolved/active status |
| `j` / `k` | Jump to next/previous comment |
| `a` | Add new comment (switches to source) |
| `q` | Close panel |

## Commands

All actions are also available as commands:

```
:CommentAdd          Add comment (supports range in visual mode)
:CommentEdit         Edit comment under cursor
:CommentDelete       Delete comment under cursor
:CommentPreview      Preview comment in floating window
:CommentResolve      Toggle resolved status
:CommentList         Toggle comment list panel
:CommentNext         Jump to next comment
:CommentPrev         Jump to previous comment
:CommentToggleSigns  Toggle highlight/sign visibility
```

## Configuration

All options are optional. These are the defaults:

```lua
require("comment-overlay").setup({
  signs = {
    enabled = true,
    icon = "󰆉",           -- nerd font comment icon
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
    position = "right",   -- "right", "left", or "bottom"
    width = 40,
    height = 15,           -- for bottom position
    auto_preview = true,
  },
  storage = {
    path = nil,            -- auto-detect project root via .git
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
})
```

## Storage

Comments are stored in `.nvim-comments.json` at the project root (auto-detected via `.git` directory). The file is human-readable JSON — you can commit it to share comments with your team or add it to `.gitignore`.

## License

MIT

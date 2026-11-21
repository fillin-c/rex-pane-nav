# rex-pane-nav

Move between Neovim windows, [Rex](https://www.superlogical.com/rex) panes and
Rex tabs with one set of keys: `shift+cmd+h/j/k/l` by default.

- In a Neovim pane, the key is sent to Neovim as `ctrl+h/j/k/l`. Neovim moves
  between its own windows, and at its edge hands off to Rex.
- In any other pane (a shell, Claude Code, …), the key moves between Rex panes.
  `ctrl+h/j/k/l` stays untouched there.
- At the outer edge along the tab bar, it moves to the next tab, and past the
  last tab to the next session.

Inspired by [vim-tmux-navigator](https://github.com/christoomey/vim-tmux-navigator)
and [rex-navigator.nvim](https://github.com/baggiponte/rex-navigator.nvim).

## Install

### Rex

```sh
git clone https://github.com/fillin-c/rex-pane-nav ~/.local/share/rex-pane-nav
```

In `~/.config/rex/init.lua`:

```lua
dofile(os.getenv("HOME") .. "/.local/share/rex-pane-nav/rex/pane_nav.lua").setup{
  mods = "shift+cmd",   -- modifiers for h/j/k/l
  tabs = "horizontal",  -- your tab bar: "horizontal", "vertical", or false to never leave the tab
  wrap = true,          -- wrap around panes inside a tab
}
```

Then `rex config reload`. `tabs` can also be a function returning one of those
values, if you switch tab styles.

### Neovim

With [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{ "fillin-c/rex-pane-nav", main = "rex-pane-nav", lazy = false, opts = {} }
```

The plugin maps `ctrl+h/j/k/l` in normal and terminal mode, only inside Rex.
It calls the `rex` CLI (from `$REX_BIN_DIR` or `PATH`) when there is no window
in that direction.

LazyVim maps `ctrl+h/j/k/l` itself after plugins load. Map them again in
`lua/config/keymaps.lua`:

```lua
for _, key in ipairs({ "h", "j", "k", "l" }) do
  vim.keymap.set("n", "<C-" .. key .. ">", function() require("rex-pane-nav").navigate(key) end)
end
```

## License

[0BSD](LICENSE): use, copy and change it freely, with no attribution needed.

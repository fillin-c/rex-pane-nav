# rex-pane-nav

Move between [Rex](https://www.superlogical.com/rex) panes, Rex tabs and
Neovim windows with one set of keys: `shift+cmd+h/j/k/l` by default.

- In a pane (a shell, Claude Code, …), the key moves between Rex panes.
  `ctrl+h/j/k/l` stays untouched there.
- At the outer edge along the tab bar, it moves to the next tab, and past the
  last tab to the next session, landing on the pane at the side it comes in
  from. After this Mac's sessions come those of your other hosts; hosts that
  can't be reached are skipped.
- In a Neovim pane, the key is sent to Neovim as `ctrl+h/j/k/l`. Neovim moves
  between its own windows, and at its edge hands off to Rex.
- In a floating Neovim window (lazygit, a picker), it does nothing until you
  close the float.

https://github.com/user-attachments/assets/44b4b6fa-6191-4742-993f-6f4bcc43bd94

Inspired by [vim-tmux-navigator](https://github.com/christoomey/vim-tmux-navigator)
and [rex-navigator.nvim](https://github.com/baggiponte/rex-navigator.nvim).

## Install

One copy of this repository serves both Rex and Neovim. Put it at
`~/.local/share/rex-pane-nav` (any path works; change it below).

With git:

```sh
git clone https://github.com/fillin-c/rex-pane-nav ~/.local/share/rex-pane-nav
```

Or with a Nix flake and home-manager:

```nix
# flake.nix
inputs.rex-pane-nav = { url = "github:fillin-c/rex-pane-nav"; flake = false; };

# home-manager module
home.file.".local/share/rex-pane-nav".source = inputs.rex-pane-nav;
```

### Rex

In `~/.config/rex/init.lua`:

```lua
dofile(os.getenv("HOME") .. "/.local/share/rex-pane-nav/rex/pane_nav.lua").setup{
  mods = "shift+cmd",   -- modifiers for h/j/k/l
  tabs = "horizontal",  -- your tab bar: "horizontal", "vertical", or false to never leave the tab
  wrap = true,          -- wrap around panes inside a tab
  rex = "rex",          -- the rex CLI, to skip hosts that can't be reached
}
```

Then `rex config reload`. `tabs` can also be a function returning one of those
values, if you switch tab styles.

The server Rex.app starts may not have `rex` on its PATH. To skip hosts that
can't be reached, give its full path, on macOS:

```lua
rex = os.getenv("HOME") .. "/Library/Application Support/com.superlogical.rex/RexServer/Versions/Current/Rex Server.app/Contents/MacOS/rex",
```

An app connected to another machine's server over Tailscale handles keys with
its own machine's config, so install it on every machine you use Rex from.

### Neovim

With [lazy.nvim](https://github.com/folke/lazy.nvim), load the same copy:

```lua
{ dir = "~/.local/share/rex-pane-nav", name = "rex-pane-nav", main = "rex-pane-nav", lazy = false, opts = {} }
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

Some plugins map these keys in their own buffers, and those maps win there.
Turn them off in that plugin. For [oil.nvim](https://github.com/stevearc/oil.nvim):

```lua
opts = { keymaps = { ["<C-h>"] = false, ["<C-l>"] = false } }
```

### Update

`git -C ~/.local/share/rex-pane-nav pull`, or `nix flake update rex-pane-nav`
and switch. Then `rex config reload` and restart Neovim.

## Development

`nvim -l tests/run.lua` runs the tests. They need only Neovim 0.10 or later.

## License

[0BSD](LICENSE): use, copy and change it freely, with no attribution needed.

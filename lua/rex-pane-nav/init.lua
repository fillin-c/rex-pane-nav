local M = {}

local KEYS = { h = "left", j = "down", k = "up", l = "right" }

local function rex_edge(dir)
  local rex = vim.env.REX_BIN_DIR and (vim.env.REX_BIN_DIR .. "/rex") or "rex"
  vim.system({ rex, "--autostart=false", "do", "-s", vim.env.REX_SESSION, "-b", vim.env.REX_BLOCK, "pane_nav_edge_" .. dir })
end

function M.navigate(key)
  local win = vim.api.nvim_get_current_win()
  -- from a float (lazygit, pickers) wincmd moves the windows behind it
  if vim.api.nvim_win_get_config(win).relative ~= "" then return end
  vim.cmd.wincmd(key)
  if vim.api.nvim_get_current_win() == win then
    rex_edge(KEYS[key])
  end
end

function M.setup()
  if (vim.env.REX_SESSION or "") == "" or (vim.env.REX_BLOCK or "") == "" then return end
  for key, dir in pairs(KEYS) do
    local desc = "Navigate " .. dir .. " through Neovim and Rex"
    local lhs = "<C-" .. key .. ">"
    vim.keymap.set({ "n", "i", "v", "t" }, lhs, function() M.navigate(key) end, { desc = desc })
    -- ctrl+j after an operator deletes lines, and on the command line runs it
    vim.keymap.set("o", lhs, "<Esc>", { desc = desc })
    vim.keymap.set("c", lhs, "<Nop>", { desc = desc })
  end
end

return M

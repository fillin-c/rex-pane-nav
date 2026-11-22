return function(test, eq, root)
  local log = vim.fn.tempname()

  -- A Neovim of its own, so that modes and keys behave as they do for a person
  local function child(env)
    local ch = vim.fn.jobstart({ "nvim", "--embed", "--headless", "-u", "NONE" }, {
      rpc = true,
      env = env or { REX_SESSION = "s1", REX_BLOCK = "b1", REX_BIN_DIR = root .. "/tests/bin", REX_STUB_LOG = log },
    })
    local c = {}
    function c.lua(code) return vim.rpcrequest(ch, "nvim_exec_lua", code, {}) end
    function c.keys(keys)
      vim.rpcrequest(ch, "nvim_input", keys)
      -- a round trip lets the keys be handled before the next request
      vim.rpcrequest(ch, "nvim_eval", "1")
    end
    function c.mode() return vim.rpcrequest(ch, "nvim_get_mode").mode end
    function c.close() vim.fn.jobstop(ch) end
    c.lua(("vim.opt.rtp:prepend(%q); require('rex-pane-nav').setup()"):format(root))
    return c
  end

  -- What the plugin asked the rex CLI for, once want lines have arrived
  local function handoffs(want)
    vim.wait(want > 0 and 2000 or 200, function()
      return vim.fn.filereadable(log) == 1 and #vim.fn.readfile(log) >= want
    end)
    local lines = vim.fn.filereadable(log) == 1 and vim.fn.readfile(log) or {}
    vim.fn.delete(log)
    return lines
  end

  test("it moves between Neovim windows without asking Rex", function()
    local c = child()
    c.lua("vim.cmd('rightbelow vnew'); vim.cmd.wincmd('h')")
    c.keys("<C-l>")
    eq(c.lua("return vim.fn.winnr()"), 2)
    eq(handoffs(0), {})
    c.close()
  end)

  test("at Neovim's edge it hands off to Rex", function()
    local c = child()
    c.keys("<C-h>")
    eq(handoffs(1), { "--autostart=false do -s s1 -b b1 pane_nav_edge_left" })
    c.close()
  end)

  test("in a floating window it stays put", function()
    local c = child()
    c.lua("vim.api.nvim_open_win(vim.api.nvim_create_buf(false, true), true, { relative = 'editor', row = 1, col = 1, width = 20, height = 5 })")
    c.keys("<C-h>")
    eq(handoffs(0), {})
    c.close()
  end)

  test("outside Rex it maps nothing", function()
    local c = child({ REX_SESSION = "", REX_BLOCK = "" })
    eq(c.lua("return vim.fn.maparg('<C-h>', 'n')"), "")
    c.close()
  end)

  local FLOAT = "vim.api.nvim_open_win(vim.api.nvim_create_buf(false, true), true, { relative = 'editor', row = 1, col = 1, width = 20, height = 5 })"

  test("in a floating terminal it stays in terminal mode", function()
    local c = child()
    c.lua(FLOAT .. "; vim.fn.termopen({ 'cat' })")
    c.keys("i")
    c.keys("<C-h>")
    eq(c.mode(), "t")
    eq(handoffs(0), {})
    c.close()
  end)

  test("at the edge a terminal hands off and stays in terminal mode", function()
    local c = child()
    c.lua("vim.fn.termopen({ 'cat' })")
    c.keys("i")
    c.keys("<C-h>")
    eq(c.mode(), "t")
    eq(handoffs(1), { "--autostart=false do -s s1 -b b1 pane_nav_edge_left" })
    c.close()
  end)
end

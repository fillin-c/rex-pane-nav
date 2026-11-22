return function(test, eq, root)
  local function pane(id, x, w) return { block_id = id, rect = { x, 0, w, 1 } } end
  local function tab(id, layout) return { window_id = id, layers = { { kind = "tiled", layout = layout } } } end
  local function halves(a, b) return { split = { before = pane(a, 0, 0.5), after = pane(b, 0.5, 0.5) } } end

  -- s1 has tabs w1 (b1 | b2) and w2 (b3 | b4); s2 has tab w3 (b5)
  local VIEWS = {
    s1 = { windows = { tab("w1", halves("b1", "b2")), tab("w2", halves("b3", "b4")) } },
    s2 = { windows = { tab("w3", pane("b5", 0, 1)) } },
  }

  -- Loads rex/pane_nav.lua against a fake rex global and presses an action.
  -- t.exec(argv) answers the rex CLI; without it there is no CLI
  local function load(t)
    t = t or {}
    local env = { actions = {}, binds = {}, queued = {}, calls = {}, execs = {} }
    _G.rex = {
      action = function(a) env.actions[a.name] = a end,
      bind = function(key, name) env.binds[key] = name end,
      client = { queue = function(action, args) env.queued[#env.queued + 1] = { action, args } end },
      block = {
        call = function(_, method)
          if method == "process" then return { foreground = { name = t.foreground or "zsh" } } end
          return {}
        end,
      },
      call = function(method, args)
        env.calls[#env.calls + 1] = { method, args }
        if method == "session.view" then return VIEWS[args.session_id] end
        if method == "session.list" then return { sessions = { { session_id = "s1" }, { session_id = "s2" } } } end
        return {}
      end,
      exec = function(argv)
        env.execs[#env.execs + 1] = argv
        local out = t.exec and t.exec(argv)
        return out and { ok = true, stdout = vim.json.encode(out) } or nil
      end,
      json = { encode = vim.json.encode, decode = vim.json.decode },
    }
    dofile(root .. "/rex/pane_nav.lua").setup(t.opts)
    function env.press(name, block_id, session_id)
      env.queued = {}
      env.actions[name].run({ session_id = session_id or "s1", block_id = block_id, client_id = "c1" })
      return env.queued
    end
    return env
  end

  test("setup binds shift+cmd+h/j/k/l to the four actions", function()
    local env = load()
    eq(env.binds, {
      ["shift+cmd+h"] = "pane_nav_left", ["shift+cmd+j"] = "pane_nav_down",
      ["shift+cmd+k"] = "pane_nav_up", ["shift+cmd+l"] = "pane_nav_right",
    })
    eq(env.actions.pane_nav_edge_left ~= nil, true)
  end)

  test("in a Neovim pane the key is sent on as ctrl+key", function()
    eq(load({ foreground = "nvim" }).press("pane_nav_left", "b1"), { { "pane.send_key", { key = "ctrl+h" } } })
  end)

  test("inside a tab it moves between panes", function()
    eq(load().press("pane_nav_right", "b1"), { { "pane.focus", { direction = "right", wrap = true } } })
  end)

  test("off the tab bar's axis it stays in the tab", function()
    eq(load().press("pane_nav_up", "b1"), { { "pane.focus", { direction = "up", wrap = true } } })
  end)

  test("tabs = false never leaves the tab", function()
    eq(load({ opts = { tabs = false } }).press("pane_nav_right", "b2"), { { "pane.focus", { direction = "right", wrap = true } } })
  end)

  test("at the right edge it enters the next tab on its left pane", function()
    local env = load()
    eq(env.press("pane_nav_right", "b2"), { { "session.select", { session_id = "s1", window_id = "w2" } } })
    eq(env.calls[#env.calls], { "session.focus_block", { session_id = "s1", block_id = "b3" } })
  end)

  test("at the left edge it enters the previous tab on its right pane", function()
    local env = load()
    eq(env.press("pane_nav_left", "b3"), { { "session.select", { session_id = "s1", window_id = "w1" } } })
    eq(env.calls[#env.calls], { "session.focus_block", { session_id = "s1", block_id = "b2" } })
  end)

  test("past the last tab it enters the next session", function()
    eq(load().press("pane_nav_right", "b4"), { { "session.select", { session_id = "s2", window_id = "w3" } } })
  end)

  test("past the last session without the CLI it asks the app for the next session", function()
    eq(load().press("pane_nav_right", "b5", "s2"), { { "session.next", {} } })
  end)

  test("a failed lookup of the app's label is tried again on the next key", function()
    local inspects = 0
    local env = load({
      exec = function(argv)
        if argv[2] == "hosts" then return { hosts = { { label = "box", status = "reachable" } } } end
        local method = argv[#argv - 1]
        if method == "session.list" then return { sessions = { { session_id = "r1" } } } end
        if method == "session.view" then return { windows = { tab("w9", pane("b9", 0, 1)) } } end
        if method == "client.inspect" then
          inspects = inspects + 1
          return inspects > 1 and { client = { info = { label = "mac" } } } or nil
        end
        if method == "client.list" then
          return { clients = { { client_id = "p1", connection_state = "connected", info = { label = "mac" } } } }
        end
        return {}
      end,
    })
    eq(env.press("pane_nav_right", "b5", "s2"), { { "session.next", {} } })
    eq(env.press("pane_nav_right", "b5", "s2"), {})
    local last = env.execs[#env.execs]
    eq({ last[2], last[3], last[#last - 1] }, { "-S", "box", "client.perform" })
  end)
end

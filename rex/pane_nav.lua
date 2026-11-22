local M = {}

local KEYS = { h = "left", j = "down", k = "up", l = "right" }

local TAB_STEP = {
  vertical   = { up = -1, down = 1 },
  horizontal = { left = -1, right = 1 },
}

local function in_nvim(ctx)
  local p = rex.block.call("com.superlogical.terminal", "process", { session_id = ctx.session_id, block_id = ctx.block_id })
  if not p then return false end
  if p.foreground and p.foreground.name == "nvim" then return true end
  for _, a in ipairs(p.ancestors or {}) do
    if a.name == "nvim" then return true end
  end
  return false
end

local function find_rect(node, block_id)
  if not node then return nil end
  if node.block_id == block_id then return node.rect end
  if node.split then
    return find_rect(node.split.before, block_id) or find_rect(node.split.after, block_id)
  end
end

local function window_of(v, block_id)
  for _, w in ipairs(v and v.windows or {}) do
    for _, l in ipairs(w.layers or {}) do
      if l.kind == "tiled" and find_rect(l.layout, block_id) then return w end
    end
  end
end

local function at_edge(v, block_id, dir)
  for _, w in ipairs(v and v.windows or {}) do
    for _, l in ipairs(w.layers or {}) do
      local r = l.kind == "tiled" and find_rect(l.layout, block_id)
      if r then
        local x, y, wd, ht = r[1], r[2], r[3], r[4]
        -- 1e-6: rects are normalized floats, so a pane on the edge can be off by rounding
        if dir == "left" then return x <= 1e-6 end
        if dir == "right" then return x + wd >= 1 - 1e-6 end
        if dir == "up" then return y <= 1e-6 end
        return y + ht >= 1 - 1e-6
      end
    end
  end
  return false
end

local function client_ops(send)
  return {
    focus   = function(_, dir, wrap) send("pane.focus", { direction = dir, wrap = wrap }) end,
    session = function(_, step) send(step > 0 and "session.next" or "session.previous", {}) end,
    select  = function(_, id, window_id) send("session.select", { session_id = id, window_id = window_id }) end,
  }
end

local QUEUE = client_ops(function(action, args) rex.client.queue(action, args) end)

-- A handoff from a Neovim edge comes through the CLI, so there is no app to queue to, and
-- the key may have been handled by another server's config (an app connected over
-- Tailscale). The pane's owner is the app showing it, so ask that app to move
local function owner_ops(ctx)
  local size = rex.block.call("com.superlogical.terminal", "size", { session_id = ctx.session_id, block_id = ctx.block_id })
  if size and size.owner then
    return client_ops(function(action, args)
      rex.call("client.perform", { client_id = size.owner, session_id = ctx.session_id, block_id = ctx.block_id, action = action, args = args })
    end)
  end
  return {
    focus   = function(_, dir, wrap) rex.call("session.focus_direction", { session_id = ctx.session_id, direction = dir, wrap = wrap }) end,
    session = function() end,
    select  = function(_, id, window_id)
      if id == ctx.session_id and window_id then rex.call("session.focus_window", { session_id = id, window_id = window_id }) end
    end,
  }
end

local ENTERS_FIRST = {
  down  = function(a, b) return a[2] < b[2] or a[2] == b[2] and a[1] < b[1] end,
  up    = function(a, b) return a[2] + a[4] > b[2] + b[4] or a[2] + a[4] == b[2] + b[4] and a[1] < b[1] end,
  right = function(a, b) return a[1] < b[1] or a[1] == b[1] and a[2] < b[2] end,
  left  = function(a, b) return a[1] + a[3] > b[1] + b[3] or a[1] + a[3] == b[1] + b[3] and a[2] < b[2] end,
}

-- The pane on the side of the window a move in dir comes in from, top-left first
local function entry_block(w, dir)
  local best
  local function walk(node)
    if not node then return end
    if node.block_id then
      if not best or ENTERS_FIRST[dir](node.rect, best.rect) then best = node end
    elseif node.split then
      walk(node.split.before)
      walk(node.split.after)
    end
  end
  for _, l in ipairs(w and w.layers or {}) do
    if l.kind == "tiled" then walk(l.layout) end
  end
  return best and best.block_id
end

-- host nil is this Mac's server
local function rex_json(bin, host, ...)
  local argv = host and { bin, "-S", host, ... } or { bin, ... }
  local r = rex.exec(argv)
  return r and r.ok and rex.json.decode(r.stdout) or nil
end

-- Sessions on the other hosts that can be reached, in sidebar order, or nil without the CLI.
-- 300ms: the check waits this long on every crossing while a host is down
local function remote_sessions(bin)
  local c = rex_json(bin, nil, "hosts", "check", "--json", "--timeout", "300ms")
  if not c then return nil end
  local out = {}
  for _, h in ipairs(c.hosts or {}) do
    if h.status == "reachable" then
      local l = rex_json(bin, h.label, "api", "call", "session.list", "{}")
      for _, s in ipairs(l and l.sessions or {}) do
        s.host = h.label
        out[#out + 1] = s
      end
    end
  end
  return out
end

local function connected_client(bin, host, match)
  for _, c in ipairs((rex_json(bin, host, "client", "ls", "--json") or {}).clients or {}) do
    if c.connection_state == "connected" and match(c) then return c end
  end
end

-- The app reaches each host through a client of its own there, under the same label
local function select_via(bin, ctx, host, id, window_id)
  local me = connected_client(bin, nil, function(c) return c.client_id == ctx.client_id end)
  local label = me and me.info and me.info.label
  local there = label and connected_client(bin, host, function(c) return c.info and c.info.label == label end)
  if not there then return false end
  return rex_json(bin, host, "api", "call", "client.perform", rex.json.encode{
    client_id = there.client_id, action = "session.select", args = { session_id = id, window_id = window_id },
  }) ~= nil
end

local function move(ctx, dir, opts, ops)
  local tabs = type(opts.tabs) == "function" and opts.tabs() or opts.tabs
  local step = TAB_STEP[tabs] and TAB_STEP[tabs][dir]
  -- host nil is this Mac's server. A key in a session on another host sets ctx.server and
  -- sends rex.call there; rex.session.view only sees the session the key came from
  local function view(host, id)
    if not host and id == ctx.session_id then return rex.session.view{ session_id = id } end
    return rex_json(opts.rex, host, "api", "call", "session.view", rex.json.encode{ session_id = id })
  end
  local function enter(host, id, w)
    local b = entry_block(w, dir)
    if b and not host and id == ctx.session_id then
      rex.session.focus_block{ session_id = id, block_id = b }
    elseif b then
      rex_json(opts.rex, host, "api", "call", "session.focus_block", rex.json.encode{ session_id = id, block_id = b })
    end
    if not host and not ctx.server then return ops.select(ctx, id, w and w.window_id) or true end
    return select_via(opts.rex, ctx, host, id, w and w.window_id)
  end

  local v = view(ctx.server, ctx.session_id)
  if not (step and at_edge(v, ctx.block_id, dir)) then
    return ops.focus(ctx, dir, opts.wrap)
  end
  local ws = v.windows
  -- not active_window_id: another host's server doesn't follow the tab this app shows
  local cur = window_of(v, ctx.block_id)
  for n, w in ipairs(ws) do
    if w == cur and ws[n + step] then
      return enter(ctx.server, ctx.session_id, ws[n + step])
    end
  end

  local mine
  if ctx.server then mine = rex_json(opts.rex, nil, "api", "call", "session.list", "{}") else mine = rex.call("session.list", {}) end
  local all = (mine or {}).sessions or {}
  local here
  for n, s in ipairs(all) do
    if not ctx.server and s.session_id == ctx.session_id then here = n end
  end
  if not (here and all[here + step]) then
    local rs = remote_sessions(opts.rex)
    if not rs then return ops.session(ctx, step) end
    for _, s in ipairs(rs) do
      all[#all + 1] = s
      if s.host == ctx.server and s.session_id == ctx.session_id then here = #all end
    end
  end
  if not here then return ops.session(ctx, step) end
  local t = all[here + step] or all[step > 0 and 1 or #all]
  local tw = (view(t.host, t.session_id) or {}).windows or {}
  if not enter(t.host, t.session_id, tw[step > 0 and 1 or #tw]) then ops.session(ctx, step) end
end

-- opts.mods: modifiers for h/j/k/l, default "shift+cmd"
-- opts.tabs: "horizontal" | "vertical" | false, or a function returning one; at the
--   outer edge along the tab bar, move to the next tab, then the next session
-- opts.wrap: wrap around panes when not moving tabs, default true
-- opts.rex: the rex CLI, used to move across sessions on other hosts and skip the ones that
--   can't be reached; default $REX_BIN_DIR/rex or rex, which the server Rex.app starts may
--   not have on its PATH
function M.setup(opts)
  opts = opts or {}
  local mods = opts.mods or "shift+cmd"
  opts.tabs = opts.tabs == nil and "horizontal" or opts.tabs
  opts.wrap = opts.wrap ~= false
  opts.rex = opts.rex or (os.getenv("REX_BIN_DIR") and os.getenv("REX_BIN_DIR") .. "/rex") or "rex"

  for key, dir in pairs(KEYS) do
    rex.action{
      name    = "pane_nav_" .. dir,
      title   = "Navigate " .. dir .. " through Neovim, Rex panes and tabs",
      repeats = true,
      run     = function(ctx)
        if in_nvim(ctx) then
          rex.client.queue("pane.send_key", { key = "ctrl+" .. key })
        else
          move(ctx, dir, opts, QUEUE)
        end
      end,
    }
    -- called by the Neovim plugin when it has no window in that direction
    rex.action{
      name  = "pane_nav_edge_" .. dir,
      title = "Navigate " .. dir .. " from a Neovim edge",
      run   = function(ctx) move(ctx, dir, opts, owner_ops(ctx)) end,
    }
    rex.bind(mods .. "+" .. key, "pane_nav_" .. dir)
  end
end

return M

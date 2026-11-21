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

local function at_edge(ctx, dir)
  local v = rex.session.view{ session_id = ctx.session_id }
  for _, w in ipairs(v and v.windows or {}) do
    for _, l in ipairs(w.layers or {}) do
      local r = l.kind == "tiled" and find_rect(l.layout, ctx.block_id)
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
    tab     = function(_, step) send(step > 0 and "client.tab.next" or "client.tab.previous", {}) end,
    session = function(_, step) send(step > 0 and "session.next" or "session.previous", {}) end,
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
    tab     = function(_, step) rex.call(step > 0 and "session.focus_next_window" or "session.focus_previous_window", { session_id = ctx.session_id }) end,
    session = function() end,
  }
end

local function move(ctx, dir, opts, ops)
  local tabs = type(opts.tabs) == "function" and opts.tabs() or opts.tabs
  local step = TAB_STEP[tabs] and TAB_STEP[tabs][dir]
  if not (step and at_edge(ctx, dir)) then
    return ops.focus(ctx, dir, opts.wrap)
  end
  local v = rex.session.view{ session_id = ctx.session_id }
  local ws = v and v.windows or {}
  for n, w in ipairs(ws) do
    if w.window_id == v.active_window_id and ws[n + step] then
      return ops.tab(ctx, step)
    end
  end
  ops.session(ctx, step)
end

-- opts.mods: modifiers for h/j/k/l, default "shift+cmd"
-- opts.tabs: "horizontal" | "vertical" | false, or a function returning one; at the
--   outer edge along the tab bar, move to the next tab, then the next session
-- opts.wrap: wrap around panes when not moving tabs, default true
function M.setup(opts)
  opts = opts or {}
  local mods = opts.mods or "shift+cmd"
  opts.tabs = opts.tabs == nil and "horizontal" or opts.tabs
  opts.wrap = opts.wrap ~= false

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

local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
local failed, count = 0, 0

local function test(name, fn)
  count = count + 1
  local ok, err = xpcall(fn, debug.traceback)
  if not ok then
    failed = failed + 1
    io.stderr:write("FAIL " .. name .. "\n" .. err .. "\n")
  end
end

local function eq(got, want)
  if not vim.deep_equal(got, want) then
    error("got " .. vim.inspect(got) .. ", want " .. vim.inspect(want), 2)
  end
end

for _, spec in ipairs({ "rex_spec", "nvim_spec" }) do
  dofile(root .. "/tests/" .. spec .. ".lua")(test, eq, root)
end

io.stdout:write(("%d tests, %d failed\n"):format(count, failed))
os.exit(failed == 0 and 0 or 1)

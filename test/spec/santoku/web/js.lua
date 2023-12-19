local assert = require("luassert")
local test = require("santoku.test")
-- local compat = require("santoku.compat")
-- local gen = require("santoku.gen")
-- local vec = require("santoku.vector")
local val = require("santoku.web.val")
local js = require("santoku.web.js")

collectgarbage("stop")

test("js", function ()

  -- -- test("x:lua(true) converts the val to a lua table", function ()
  -- --   -- TODO
  -- -- end)

  -- TODO: This doesn't seem to work in lua 5.1, what is the difference in terms
  -- of calling unpack on a userdata in 5.1 vs 5.4?
  --
  -- test("unpack a javascript array", function ()
  --   local arr = val({ 1, 2, 3 }, true)
  --   arr = arr:lua()
  --   local a, b, c = compat.unpack(arr)
  --   assert.same({ 1, 2, 3 }, { a, b, c })
  -- end)
  -- test("pairs over a javascript object", function ()
  --   local obj = val({ a = 1 }, true):lua()
  --   assert.same({{"a", 1, n = 2}, n = 1}, gen.pairs(obj):vec())
  -- end)
  -- test("Object.keys() on wrapped val", function ()
  --   local obj = val({ a = 1, b = 2 })
  --   local keys = js.Object:keys(obj)
  --   local vkeys = vec(compat.unpack(keys)):sort()
  --   assert.same({ "a", "b", n = 2 }, vkeys)
  -- end)
  -- test("Object.values() on wrapped val", function ()
  --   local obj = val({ a = 1, b = 2 })
  --   local values = js.Object:values(obj)
  --   local vvalues = vec(compat.unpack(values)):sort()
  --   assert.same({ 1, 2, n = 2 }, vvalues)
  -- end)

  -- TODO: This depends on x:lua(true) working,
  -- which converts a wrapped JS object to a lua
  -- table
  --
  -- test("Object.entries() on wrapped val", function ()
  --   local obj = val({ a = 1, b = 2 })
  --   local entries = js.Object:entries(obj)
  --   print(entries:lua(true))
  -- end)

  test("equality", function ()
    local c0 = js.console
    local c1 = js.console
    assert.equals(c0:val(), c1:val())
  end)

end)

val.global("setTimeout"):call(nil, function ()

  collectgarbage("collect")
  val.global("gc"):call(nil)
  collectgarbage("collect")
  val.global("gc"):call(nil)
  collectgarbage("collect")

  val.global("setTimeout"):call(nil, function ()

    -- Note: 2 because of the two nested set timeouts
    assert.equals(2, val.IDX_REF_TBL_N)

    if os.getenv("TK_WEB_PROFILE") == "1" then
      require("santoku.profile")()
    end

  end)

end, 500)

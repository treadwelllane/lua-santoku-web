local assert = require("luassert")
local test = require("santoku.test")
local compat = require("santoku.compat")
local gen = require("santoku.gen")
local vec = require("santoku.vector")
local val = require("santoku.web.val")
local js = require("santoku.web.js")

test("js", function ()

  test("val(x) wraps a lua table with a proxy", function ()
    local t = { 1, { 2, 3 }, 4 }
    local v = val(t)
    assert.equals("[1,[2,3],4]", js.JSON:stringify(v))
    assert.equals(false, v:isval())
    assert.equals(true, v:islua())
  end)

  test("val(x, true) converts a lua numeric table to an array", function ()
    local t = { 1, { 2, 3 }, 4 }
    local v = val(t, true)
    assert.equals("[1,[2,3],4]", js.JSON:stringify(v))
    assert.equals(true, v:isval())
    assert.equals(false, v:islua())
  end)

  test("val(x, true) converts a lua map table to an object", function ()
    local t = { a = 1, b = { c = 3 } }
    local v = val(t, true)
    assert.equals(true, v:isval())
    assert.equals(false, v:islua())
  end)

  test("x:val() returns the val as is", function ()
    local t = { 1, { 2, 3 }, 4 }
    local v = val(t):val()
    assert.equals("[1,[2,3],4]", js.JSON:stringify(v))
    assert.equals(false, v:isval())
    assert.equals(true, v:islua())
  end)

  -- -- TODO: Why is this failing?
  -- test("x:val(true) returns the val converted to a val", function ()
  --   local t = { 1, { 2, 3 }, 4 }
  --   local v1 = val(t)
  --   assert.equals("[1,[2,3],4]", js.JSON:stringify(v1))
  --   assert.equals(false, v1:isval())
  --   assert.equals(true, v1:islua())
  --   local v2 = v1:val(true)
  --   assert.equals("[1,[2,3],4]", js.JSON:stringify(v2))
  --   assert.equals(true, v2:isval())
  --   assert.equals(false, v2:islua())
  -- end)

  -- test("x:val(true) returns the val converted to a val", function ()
  --   local t = { a = 1, b = { c = 2 } }
  --   local v = val(t):val(true)
  --   assert.equals(true, v:isval())
  --   assert.equals(false, v:islua())
  -- end)

  -- -- test("x:lua() returns a lua wrapper", function ()
  -- --   -- TODO
  -- -- end)

  -- -- test("x:lua(true) converts the val to a lua table", function ()
  -- --   -- TODO
  -- -- end)

  test("unpack a javascript array", function ()
    local arr = val({ 1, 2, 3 }, true):lua()
    local a, b, c = compat.unpack(arr)
    assert.same({ 1, 2, 3 }, { a, b, c })
  end)

  test("pairs over a javascript object", function ()
    local obj = val({ a = 1 }, true):lua()
    assert.same({{"a", 1, n = 2}, n = 1}, gen.pairs(obj):vec())
  end)

  test("Object.keys() on wrapped val", function ()
    local obj = val({ a = 1, b = 2 })
    local keys = js.Object:keys(obj)
    local vkeys = vec(compat.unpack(keys)):sort()
    assert.same({ "a", "b", n = 2 }, vkeys)
  end)

  test("Object.values() on wrapped val", function ()
    local obj = val({ a = 1, b = 2 })
    local values = js.Object:values(obj)
    local vvalues = vec(compat.unpack(values)):sort()
    assert.same({ 1, 2, n = 2 }, vvalues)
  end)

  -- TODO: This depends on x:lua(true) working,
  -- which converts a wrapped JS object to a lua
  -- table
  --
  -- test("Object.entries() on wrapped val", function ()
  --   local obj = val({ a = 1, b = 2 })
  --   local entries = js.Object:entries(obj)
  --   print(entries:lua(true))
  -- end)

end)

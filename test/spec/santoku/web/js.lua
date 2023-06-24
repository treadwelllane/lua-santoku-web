local assert = require("luassert")
local test = require("santoku.test")
local compat = require("santoku.compat")
local gen = require("santoku.gen")
local val = require("santoku.web.val")
local js = require("santoku.web.js")

-- TODO
--
-- val(x [, false]): converts lua value 'x' to a
-- javascript value, returning a val userdata.
-- If 'x' is a table, the val userdata returned
-- is a javascript Proxy object which wraps the
-- lua table.
--
-- val(x, true): similar to val(x [, false]),
-- except that if 'x' is a table, the table and
-- its keys and values are traversed and
-- converted to javascript primitives, objects,
-- and arrays by recursively calling this
-- function. Recursion stops whenever a
-- javascript value that is not a lua Proxy is
-- encountered.
--
-- x:val([, false]): called on an existing val,
-- promise, object, etc., returning it as a val.
--
-- x:val(true): called on an existing val. If
-- the val is a proxy to a lua table, behaves
-- like val(x, true), otherwise returns the val
-- as-is.
--
-- x:lua([, false]): converts a javascript value
-- to a lua value, and either returns the lua
-- primitive or a proxy-table that wraps the
-- underlying javascript object.
--
-- x:lua(true): similar to x:lua([, false]),
-- except that if the javascript value is an
-- object, the object and its keys and values
-- are traversed and converted to lua primitives
-- and tables by recursively calling this
-- function. Recursion stops whenever a lua
-- value that is not a javascript proxy is
-- encountered.

test("js", function ()

  test("val(x) wraps a lua table with a proxy", function ()
    local t = { 1, { 2, 3 }, 4 }
    local v = val(t)
    assert.equals(false, v:isval())
    assert.equals(true, v:islua())
  end)

  test("val(x, true) converts a lua numeric table to an array", function ()
    local t = { 1, { 2, 3 }, 4 }
    local v = val(t, true)
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
    assert.equals(false, v:isval())
    assert.equals(true, v:islua())
  end)

  test("x:val(true) returns the val converted to a val", function ()
    local t = { 1, { 2, 3 }, 4 }
    local v = val(t):val(true)
    assert.equals(true, v:isval())
    assert.equals(false, v:islua())
  end)

  test("x:val(true) returns the val converted to a val", function ()
    local t = { a = 1, b = { c = 2 } }
    local v = val(t):val(true)
    assert.equals(true, v:isval())
    assert.equals(false, v:islua())
  end)

  -- test("x:lua() returns a lua wrapper", function ()
  --   -- TODO
  -- end)

  -- test("x:lua(true) converts the val to a lua table", function ()
  --   -- TODO
  -- end)

  test("unpack a javascript array", function ()
    local arr = val({ 1, 2, 3 }, true):lua()
    local a, b, c = compat.unpack(arr)
    assert.same({ 1, 2, 3 }, { a, b, c })
  end)

  test("pairs over a javascript object", function ()
    local obj = val({ a = 1 }, true):lua()
    assert.same({{"a", 1, n = 2}, n = 1}, gen.pairs(obj):vec())
  end)

end)

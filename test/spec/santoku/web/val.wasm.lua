local test = require("santoku.test")
local str = require("santoku.string")
local tbl = require("santoku.table")
local err = require("santoku.error")
local validate = require("santoku.validate")
local val = require("santoku.web.val")

local assert = err.assert
local eq = validate.isequal
local teq = tbl.equals

collectgarbage("stop")

test("global", function ()

  test("returns a global object (simple)", function ()
    local c0 = val.global("console")
    local v0 = c0:lua()
    assert(eq("object", v0:typeof()))
  end)

  test("returns a global object (duplicated)", function ()
    local c0 = val.global("console")
    local v0 = c0:lua()
    local c1 = val.global("console")
    local v1 = c1:lua()
    local c2 = val.global("console")
    local v2 = c2:lua()
    assert(eq("object", v0:typeof()))
    assert(eq("object", v1:typeof()))
    assert(eq("object", v2:typeof()))
  end)

  test("val.global(x):lua() == val.global(x):lua()", function ()
    local a = val.global("console"):lua()
    local b = val.global("console"):lua()
    assert(eq(a, b))
  end)

end)

test("from string", function ()

  test("creates a string value", function ()
    local a = val("hello")
    assert(eq("string", a:typeof():lua()))
    assert(eq("hello", a:lua()))
  end)

end)

test("from number", function ()

  test("creates a number value", function ()
    local a = val(100.6)
    assert(eq("number", a:typeof():lua()))
    assert(eq(100.6, a:lua()))
  end)

end)

test("from boolean", function ()

  -- TODO: Booleans come back as a number
  test("creates a boolean value", function ()
    local a = val(true)
    assert(eq("boolean", a:typeof():lua()))
    assert(eq(true, a:lua()))
    local a = val(false)
    assert(eq("boolean", a:typeof():lua()))
    assert(eq(false, a:lua()))
  end)

end)

test("from table", function ()

  test("creates an object proxy", function ()
    local source = { a = 1, b = "2" }
    local a = val(source)
    assert(eq("object", a:typeof():lua()))
    assert(eq(source, a:lua()))
    assert(teq({ a = 1, b = "2" }, a:lua()))
    a:set("c", 3)
    assert(eq(source, a:lua()))
    assert(teq({ a = 1, b = "2", c = 3 }, a:lua()))
  end)

  test("creates an array proxy", function ()
    local source = { 1, 2, 3, 4 }
    local a = val(source)
    assert(eq("object", a:typeof():lua()))
    assert(eq(source, a:lua()))
    assert(teq({ 1, 2, 3, 4 }, a:lua()))
  end)

  test("array proxy get adds 1 to numeric keys", function ()
    local source = { 1, 2, 3, 4 }
    local a = val(source)
    assert(eq(1, a:get(0):lua()))
    assert(eq(2, a:get(1):lua()))
    assert(eq(3, a:get(2):lua()))
    assert(eq(4, a:get(3):lua()))
  end)

  test("array proxy set adds 1 to numeric keys", function ()
    local source = {}
    local a = val(source)
    a:set(0, 1)
    assert(eq(1, a:lua()[1]))
  end)

end)

test("from function", function ()
  local fn = function (a) return a + 4 end
  local a = val(fn)
  assert(eq("function", a:typeof():lua()))
  assert(eq(fn, a:lua()))
  local x = a:lua()(2)
  assert(eq(6, x))
end)

test("object set/get", function ()
  local obj = val.global("Object"):call(nil)
  obj:set("a", 1)
  local one = obj:get("a")
  assert(eq("number", one:typeof():lua()))
  assert(eq(1, one:lua()))
end)

test("JSON.stringify({})", function ()
  local obj = val.global("Object"):call(nil)
  local JSON = val.global("JSON")
  local stringify = JSON:get("stringify")
  local r = stringify:call(JSON, obj)
  assert(eq("string", r:typeof():lua()))
  assert(eq("{}", r:lua()))
end)

test("JSON.stringify nested :lua()", function ()
  local JSON = val.global("JSON"):lua()
  local r = JSON:stringify({ a = { b = 1 } })
  assert(eq("{\"a\":{\"b\":1}}", r))
end)

test("JSON.stringify array :lua()", function ()
  local JSON = val.global("JSON"):lua()
  local r = JSON:stringify({ 1, 2, 3, 4 })
  assert(eq("[1,2,3,4]", r))
end)

test("JSON.stringify({}) :lua()", function ()
  local obj = val.global("Object"):call(nil)
  local JSON = val.global("JSON"):lua()
  local r = JSON:stringify(obj)
  assert(eq("{}", r))
end)

test("JSON.stringify({}) :lua() 2", function ()
  local obj = { a = 1 }
  local JSON = val.global("JSON"):lua()
  local r = JSON:stringify(obj)
  assert(eq("{\"a\":1}", r))
end)

test("JSON.stringify({}) :lua() 3", function ()
  local a = { a = 1 }
  local b = val.global("Object"):call(nil)
  b:set("a", 1)
  local JSON = val.global("JSON"):lua()
  local ar = JSON:stringify(a)
  local br = JSON:stringify(b)
  assert(eq("{\"a\":1}", ar))
  assert(eq("{\"a\":1}", br))
end)

test("Math.max(1, 3, 2)", function ()
  local Math = val.global("Math")
  local max = Math:get("max")
  local r = max:call(Math, 1, 2, 3)
  assert(eq(3, r:lua()))
end)

test("Math.max(1, 3, 2) :lua()", function ()
  local vMath = val.global("Math")
  local Math = vMath:lua()
  local r = Math:max(1, 3, 2)
  assert(eq(3, r))
end)

test("new Map()", function ()
  local Map = val.global("Map")
  local m = Map:new()
  assert(eq("object", m:typeof():lua()))
  local set = m:get("set")
  set:call(m, 1, 2)
  local get = m:get("get")
  local r = get:call(m, 1)
  assert(eq("number", r:typeof():lua()))
  assert(eq(2, r:lua()))
end)

test("new Map() :lua()", function ()
  local Map = val.global("Map"):lua()
  local m = Map:new()
  assert(eq("object", m:typeof()))
  m:set(1, 2)
  local r = m:get(1)
  assert(eq(2, r))
end)

test("new Map([[1, 2], [3, 4]])", function ()

  local arr = val.global("Array"):call(nil)
  local arrpush = arr:get("push")

  local ent1 = val.global("Array"):call(nil)
  local ent1push = ent1:get("push")

  local ent2 = val.global("Array"):call(nil)
  local ent2push = ent2:get("push")

  ent1push:call(ent1, 1)
  ent1push:call(ent1, 2)
  arrpush:call(arr, ent1)

  ent2push:call(ent2, 3)
  ent2push:call(ent2, 4)
  arrpush:call(arr, ent2)

  local Map = val.global("Map")
  local m = Map:new(arr)
  local mget = m:get("get")

  assert(eq("object", m:typeof():lua()))

  local r = mget:call(m, 1)
  assert(eq("number", r:typeof():lua()))
  assert(eq(2, r:lua()))

  local r = mget:call(m, 3)
  assert(eq("number", r:typeof():lua()))
  assert(eq(4, r:lua()))

end)

-- NOTE: When calling a lua function from
-- javascript, the lua function receives it's
-- arguments as lua values and returns a lua
-- value, but that returned lua value appears
-- in the javascript world as a javascript
-- value.
test("set & call function", function ()

  local obj = val.global("Object"):call(nil)

  obj:set("square", function (_, n)
    -- TODO: When val comparisons work,
    -- this should work
    -- assert(eq(obj, this:val()))
    assert(eq(20, n))
    return n * n
  end)

  local sq = obj:get("square")

  local ret = sq:call(obj, 20)

  assert(eq(400, ret:lua()))

end)

test("instanceof", function ()
  local Map = val.global("Map"):lua()
  local m = Map:new()
  assert(m:instanceof(Map))
end)

test("array keys", function ()
  local t = { 1, 2, 3, 4, 5 }
  local vObject = val.global("Object")
  local Object = vObject:lua()
  local ki = 0
  Object:keys(t):forEach(function (_, k)
    assert(eq(ki .. "", k))
    ki = ki + 1
  end)
  assert(eq(ki, 5))
end)

test("array vals", function ()
  local t = { 1, 2, 3, 4, 5 }
  local Object = val.global("Object")
  local vi = 1
  -- TODO: should be this:
  -- Object:lua():values(t):forEach(function (_, v)
  Object:get("values"):call(nil, t):lua():forEach(function (_, v)
    assert(eq(vi, v))
    vi = vi + 1
  end)
  assert(eq(vi, 6))
end)

test("array iterator", function ()
  local a = val({ 1, 2, 3, 4, 5 })
  local Iterator = val.global("Symbol"):get("iterator")
  local _ = a:get(Iterator):lua()
  -- TODO: what to check?
end)

test("bigint", function ()
  local BigInt = val.global("BigInt"):lua()
  local i = BigInt(nil, 1)
  assert(eq(1, i))
end)

test("val integer decimals", function ()
  local i = val(1):lua()
  local s = str.interp("int: %id", { id = i })
  assert(eq("int: 1", s))
end)

test("val uint8array to string", function ()
  assert(eq("", val.global("Uint8Array"):new():lua():str()))
  assert(eq("ABC", val.global("Uint8Array"):new({ 65, 66, 67 }):lua():str()))
end)

test("val string to uint8array", function ()
  local b = val.bytes("ABC")
  assert(eq(true, b:instanceof(val.global("Uint8Array"))))
  assert(eq("ABC", val.bytes("ABC"):str()))
end)

test("convert multiple objects to val", function ()
  local arr = val({ { a = 1, b = 2 }, { c = 3, d = 4 }, { e = 5, f = 6 } }, true):lua()
  assert(eq(arr[1].a, 1))
  assert(eq(arr[1].b, 2))
  assert(eq(arr[2].c, 3))
  assert(eq(arr[2].d, 4))
  assert(eq(arr[3].e, 5))
  assert(eq(arr[3].f, 6))
end)

val.global("setTimeout"):call(nil, function ()

  collectgarbage("collect")
  val.global("gc"):call(nil)
  collectgarbage("collect")
  val.global("gc"):call(nil)
  collectgarbage("collect")

  val.global("setTimeout"):call(nil, function ()

    -- Note: 2 because of the two nested setTimeouts
    assert(val.IDX_REF_TBL.n == 2, "IDX_REF_TBL.n ~= 2")

    -- TODO: Inside callbacks this won't ever be empty. How can we adjust this
    -- test to make sense for callbacks?
    -- for _ in pairs(val.EPHEMERON_IDX) do
    --   assert(false, "ephemeron table not empty")
    -- end

    if os.getenv("TK_WEB_PROFILE") == "1" then
      require("santoku.profile")()
    end

  end)

end, 500)

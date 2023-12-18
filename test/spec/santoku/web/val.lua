local assert = require("luassert")
local test = require("santoku.test")
local str = require("santoku.string")
local val = require("santoku.web.val")

collectgarbage("stop")

test("val", function ()

  test("global", function ()

    test("returns a global object (simple)", function ()
      local c0 = val.global("console")
      local v0 = c0:lua()
      assert.equals("object", v0:typeof())
    end)

    test("returns a global object (duplicated)", function ()
      local c0 = val.global("console")
      local v0 = c0:lua()
      local c1 = val.global("console")
      local v1 = c1:lua()
      local c2 = val.global("console")
      local v2 = c2:lua()
      assert.equals("object", v0:typeof())
      assert.equals("object", v1:typeof())
      assert.equals("object", v2:typeof())
    end)

    test("val.global(x):lua() == val.global(x):lua()", function ()
      local a = val.global("console"):lua()
      local b = val.global("console"):lua()
      assert.equals(a, b)
    end)

  end)

  test("from string", function ()

    test("creates a string value", function ()
      local a = val("hello")
      assert.equals("string", a:typeof():lua())
      assert.equals("hello", a:lua())
    end)

  end)

  test("from number", function ()

    test("creates a number value", function ()
      local a = val(100.6)
      assert.equals("number", a:typeof():lua())
      assert.equals(100.6, a:lua())
    end)

  end)

  test("from boolean", function ()

    -- TODO: Booleans come back as a number
    test("creates a boolean value", function ()
      local a = val(true)
      assert.equals("boolean", a:typeof():lua())
      assert.equals(true, a:lua())
      local a = val(false)
      assert.equals("boolean", a:typeof():lua())
      assert.equals(false, a:lua())
    end)

  end)

  test("from table", function ()

    test("creates an object proxy", function ()
      local source = { a = 1, b = "2" }
      local a = val(source)
      assert.equals("object", a:typeof():lua())
      assert.equals(source, a:lua())
      assert.same({ a = 1, b = "2" }, a:lua())
      a:set("c", 3)
      assert.equals(source, a:lua())
      assert.same({ a = 1, b = "2", c = 3 }, a:lua())
    end)

    test("creates an array proxy", function ()
      local source = { 1, 2, 3, 4 }
      local a = val(source)
      assert.equals("object", a:typeof():lua())
      assert.equals(source, a:lua())
      assert.same({ 1, 2, 3, 4 }, a:lua())
    end)

    test("array proxy get adds 1 to numeric keys", function ()
      local source = { 1, 2, 3, 4 }
      local a = val(source)
      assert.equals(1, a:get(0):lua())
      assert.equals(2, a:get(1):lua())
      assert.equals(3, a:get(2):lua())
      assert.equals(4, a:get(3):lua())
    end)

    test("array proxy set adds 1 to numeric keys", function ()
      local source = {}
      local a = val(source)
      a:set(0, 1)
      assert.equals(1, a:lua()[1])
    end)

  end)

  test("from function", function ()
    local fn = function (a) return a + 4 end
    local a = val(fn)
    assert.equals("function", a:typeof():lua())
    assert.equals(fn, a:lua())
    local x = a:lua()(2)
    assert.equals(6, x)
  end)

  test("object set/get", function ()
    local obj = val.global("Object"):call(nil)
    obj:set("a", 1)
    local one = obj:get("a")
    assert.equals("number", one:typeof():lua())
    assert.equals(1, one:lua())
  end)

  test("JSON.stringify({})", function ()
    local obj = val.global("Object"):call(nil)
    local JSON = val.global("JSON")
    local stringify = JSON:get("stringify")
    local r = stringify:call(JSON, obj)
    assert.equals("string", r:typeof():lua())
    assert.equals("{}", r:lua())
  end)

  test("JSON.stringify nested :lua()", function ()
    local JSON = val.global("JSON"):lua()
    local r = JSON:stringify({ a = { b = 1 } })
    assert.equals("{\"a\":{\"b\":1}}", r)
  end)

  test("JSON.stringify array :lua()", function ()
    local JSON = val.global("JSON"):lua()
    local r = JSON:stringify({ 1, 2, 3, 4 })
    assert.equals("[1,2,3,4]", r)
  end)

  test("JSON.stringify({}) :lua()", function ()
    local obj = val.global("Object"):call(nil)
    local JSON = val.global("JSON"):lua()
    local r = JSON:stringify(obj)
    assert.equals("{}", r)
  end)

  test("JSON.stringify({}) :lua() 2", function ()
    local obj = { a = 1 }
    local JSON = val.global("JSON"):lua()
    local r = JSON:stringify(obj)
    assert.equals("{\"a\":1}", r)
  end)

  test("JSON.stringify({}) :lua() 3", function ()
    local a = { a = 1 }
    local b = val.global("Object"):call(nil)
    b:set("a", 1)
    local JSON = val.global("JSON"):lua()
    local ar = JSON:stringify(a)
    local br = JSON:stringify(b)
    assert.equals("{\"a\":1}", ar)
    assert.equals("{\"a\":1}", br)
  end)

  test("Math.max(1, 3, 2)", function ()
    local Math = val.global("Math")
    local max = Math:get("max")
    local r = max:call(Math, 1, 2, 3)
    assert.equals(3, r:lua())
  end)

  test("Math.max(1, 3, 2) :lua()", function ()
    local vMath = val.global("Math")
    local Math = vMath:lua()
    local r = Math:max(1, 3, 2)
    assert.equals(3, r)
  end)

  test("new Map()", function ()
    local Map = val.global("Map")
    local m = Map:new()
    assert.equals("object", m:typeof():lua())
    local set = m:get("set")
    set:call(m, 1, 2)
    local get = m:get("get")
    local r = get:call(m, 1)
    assert.equals("number", r:typeof():lua())
    assert.equals(2, r:lua())
  end)

  test("new Map() :lua()", function ()
    local Map = val.global("Map"):lua()
    local m = Map:new()
    assert.equals("object", m:typeof())
    m:set(1, 2)
    local r = m:get(1)
    assert.equals(2, r)
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

    assert.equals("object", m:typeof():lua())

    local r = mget:call(m, 1)
    assert.equals("number", r:typeof():lua())
    assert.equals(2, r:lua())

    local r = mget:call(m, 3)
    assert.equals("number", r:typeof():lua())
    assert.equals(4, r:lua())

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
      -- assert.equals(obj, this:val())
      assert.equals(20, n)
      return n * n
    end)

    local sq = obj:get("square")

    local ret = sq:call(obj, 20)

    assert.equals(400, ret:lua())

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
      assert.equals(ki .. "", k)
      ki = ki + 1
    end)
    assert.equals(ki, 5)
  end)

  test("array vals", function ()
    local t = { 1, 2, 3, 4, 5 }
    local Object = val.global("Object")
    local vi = 1
    -- TODO: should be this:
    -- Object:lua():values(t):forEach(function (_, v)
    Object:get("values"):call(nil, t):lua():forEach(function (_, v)
      assert.equals(vi, v)
      vi = vi + 1
    end)
    assert.equals(vi, 6)
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
    assert.equals(1, i)
  end)

  test("val integer decimals", function ()
    local i = val(1):lua()
    local s = str.interp("int: %id", { id = i })
    assert.equals("int: 1", s)
  end)

  test("val uint8array to string", function ()
    assert.equals("", val.global("Uint8Array"):new():lua():str())
    assert.equals("ABC", val.global("Uint8Array"):new({ 65, 66, 67 }):lua():str())
  end)

  test("val string to uint8array", function ()
    local b = val.bytes("ABC")
    assert.equals(true, b:instanceof(val.global("Uint8Array")))
    assert.equals("ABC", val.bytes("ABC"):str())
  end)

  test("convert multiple objects to val", function ()
    local arr = val({ { a = 1, b = 2 }, { c = 3, d = 4 }, { e = 5, f = 6 } }, true):lua()
    assert.equals(arr[1].a, 1)
    assert.equals(arr[1].b, 2)
    assert.equals(arr[2].c, 3)
    assert.equals(arr[2].d, 4)
    assert.equals(arr[3].e, 5)
    assert.equals(arr[3].f, 6)
  end)

end)

collectgarbage("collect")
val.global("gc"):call(nil)

val.global("setTimeout", function ()

  local cntt = 0
  for _ in pairs(val.IDX_REF_TBL) do
    cntt = cntt + 1
  end

  assert.equals(0, cntt, "IDX_REF_TBL not clean")

end, 5000)

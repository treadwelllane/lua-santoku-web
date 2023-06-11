-- TODO: low-level binding to emscripten/val.h

local assert = require("luassert")
local test = require("santoku.test")
local val = require("santoku.web.val")

test("val", function ()

  test("val.global(x):lua() == val.global(x):lua()", function ()
    local a = val.global("console"):lua()
    local b = val.global("console"):lua()
    assert.equals(a, b)
  end)

  test("global", function ()

    test("returns a global object", function ()
      local v = val.global("console"):lua()
      assert.equals("object", v:typeof())
    end)

  end)

  test("object", function ()

    test("creates a js object", function ()
      local o = val.object()
      assert.equals("object", o:typeof():lua())
    end)

  end)

  test("array", function ()

    test("creates a js array", function ()
      local a = val.array()
      assert.equals("object", a:typeof():lua())
    end)

  end)

  test("undefined", function ()

    test("creates an undefined value", function ()
      local a = val.undefined()
      assert.equals("undefined", a:typeof():lua())
    end)

  end)

  test("null", function ()

    test("creates a null value", function ()
      local a = val.null()
      assert.equals("object", a:typeof():lua())
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

    -- TODO: Numbers lose precision round trip.
    -- Not sure why
    test("creates a number value", function ()
      local a = val(100.6)
      assert.equals("number", a:typeof():lua())
      -- assert.equals(100.6, a:lua())
    end)

  end)

  test("from boolean", function ()

    -- TODO: Booleans come back as a number
    test("creates a boolean value", function ()
      local a = val(true)
      -- assert.equals("boolean", a:typeof():lua())
      -- assert.equals(true, a:bool())
      local a = val(false)
      -- assert.equals("boolean", a:typeof():lua())
      -- assert.equals(false, a:bool())
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
      assert(1, a:get(0))
      assert(2, a:get(1))
      assert(3, a:get(2))
      assert(4, a:get(3))
    end)

    test("array proxy set adds 1 to numeric keys", function ()
      local source = {}
      local a = val(source)
      a:set(0, 1)
      assert(1, a[1])
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
    local obj = val.object()
    obj:set("a", 1)
    local one = obj:get("a")
    assert.equals("number", one:typeof():lua())
    assert.equals(1, one:lua())
  end)

  test("JSON.stringify({})", function ()
    local obj = val.object()
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
    local obj = val.object():lua()
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
    local b = val.object()
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
    local Math = val.global("Math"):lua()
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

    local arr = val.array()
    local arrpush = arr:get("push")

    local ent1 = val.array()
    local ent1push = ent1:get("push")

    local ent2 = val.array()
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

  test("set & call function", function ()

    local obj = val.object():lua()

    obj.square = function (this, n)
      assert.equals(obj, this)
      assert.equals(20, n)
      return n * n
    end

    local ret = obj:square(20)
    assert.equals(400, ret)

  end)

  test("setTimeout", function ()
    local setTimeout = val.global("setTimeout")
    setTimeout:call(nil, function (this, a, b)
      assert.equals("hello", a)
      assert.equals("world", b)
    end, 1000, "hello", "world")
  end)

  test("win:setTimeout", function ()
    local win = val.global("global"):lua()
    win:setTimeout(function (this, a, b, ...)
      assert.equals("hello", a)
      assert.equals("world", b)
    end, 1000, "hello", "world")
  end)

  test("promise", function ()
    local Promise = val.global("Promise")
    local p = Promise:new(function (this, resolve)
      resolve(this, "hello")
    end)
    local thn = p:get("then")
    thn:call(p, function (this, msg, ...)
      assert.equals("hello", msg)
    end)
  end)

  test("promise :lua()", function ()
    local Promise = val.global("Promise")
    local p = Promise:new(function (this, resolve)
      resolve(this, "hello")
    end):lua()
    p["then"](p, function (this, msg)
      assert.equals("hello", msg)
    end)
  end)

  test("await", function ()
    local setTimeout = val.global("setTimeout"):lua()
    local Promise = val.global("Promise"):lua()
    local p = Promise:new(function (this, resolve)
      setTimeout(nil, function ()
        resolve(this, "hello")
      end, 1000)
    end):await(function (this, ok, msg)
      assert.equals(true, ok)
      assert.equals("hello", msg)
    end)
  end)

  test("instanceof", function ()
    local Map = val.global("Map"):lua()
    local m = Map:new()
    assert(m:instanceof(Map))
  end)

  test("array keys", function ()
    local t = { 1, 2, 3, 4, 5 }
    local Object = val.global("Object"):lua()
    local ki = 0
    Object:keys(t):forEach(function (_, k)
      assert.equals(ki .. "", k)
      ki = ki + 1
    end)
    assert.equals(ki, 5)
  end)

  test("array vals", function ()
    local t = { 1, 2, 3, 4, 5 }
    local Object = val.global("Object"):lua()
    local vi = 1
    Object:values(t):forEach(function (_, v)
      assert.equals(vi, v)
      vi = vi + 1
    end)
    assert.equals(vi, 6)
  end)

  test("array iterator", function ()
    local a = val({ 1, 2, 3, 4, 5 })
    local Iterator = val.global("Symbol"):get("iterator")
    local it = a:get(Iterator):lua()
    -- TODO: what to check?
  end)

end)

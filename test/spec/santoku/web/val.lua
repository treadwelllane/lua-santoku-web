-- TODO: low-level binding to emscripten/val.h

local assert = require("luassert")
local test = require("santoku.test")
local val = require("santoku.web.val")

test("val", function ()

  test("val(x) == val(val(x):lua())", function ()
    local a = val.global("console"):lua()
    local b = val.global("console"):lua()
    assert.equals(a, b)
  end)

  test("global", function ()

    test("returns a global object", function ()
      local v = val.global("console")
      assert.equals("object", v:typeof():lua())
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

    -- TODO: Automatically determine if table
    -- should be mapped to an array, and
    -- optionally allow the user to override.
    --
    -- test("creates an array proxy", function ()
    --   local source = { 1, 2, 3, 4 }
    --   local a = val(source)
    --   assert.equals("object", a:typeof():lua())
    --   assert.equals(source, a:lua())
    --   assert.same({ 1, 2, 3, 4 }, a:lua())
    -- end)

  end)

  test("from function", function ()
    local fn = function (a) return a + 4 end
    local a = val(fn)
    assert.equals("function", a:typeof():lua())
    assert.equals(fn, a:lua())
    local x = a:lua()(2)
    assert.equals(6, x)
  end)

  test("object", function ()

    test("set/get", function ()
      local obj = val.object()
      obj:set("a", 1)
      local one = obj:get("a")
      assert.equals("number", one:typeof():lua())
      assert.equals(1, one:lua())
    end)

  end)

  test("call", function ()

    test("JSON.stringify({})", function ()
      local obj = val.object()
      local JSON = val.global("JSON")
      local stringify = JSON:get("stringify")
      local r = stringify:call(JSON, obj)
      assert.equals("string", r:typeof():lua())
      assert.equals("{}", r:lua())
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

  end)

  test("new", function ()

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

  test("setTimeout :lua()", function ()
    local setTimeout = val.global("setTimeout"):lua()
    setTimeout(nil, function (this, a, b)
      assert.equals("hello", a)
      assert.equals("world", b)
    end, 1000, "hello", "world")
  end)

  test("setTimeout :lua() 2", function ()
    local win = val.global("global"):lua()
    win:setTimeout(function (this, a, b, ...)
      assert.equals("hello", a)
      assert.equals("world", b)
    end, 1000, "hello", "world")
  end)

  test("promise", function ()
    local Promise = val.global("Promise")
    local p = Promise:new(function (this, resolve)
      resolve(nil, "hello")
    end)
    local thn = p:get("then")
    thn:call(p, function (this, msg, ...)
      assert.equals("hello", msg)
    end)
  end)

  test("promise :lua()", function ()
    local Promise = val.global("Promise")
    local p = Promise:new(function (this, resolve)
      resolve(nil, "hello")
    end):lua()
    p["then"](p, function (this, msg)
      assert.equals("hello", msg)
    end)
  end)

  ---- TODO:
  ---- test("await", function ()
  ----   local global = val.global("global")
  ----   local Promise = global:get("Promise")
  ----   local p = Promise:new(function (resolve)
  ----     global:call("setTimeout", function ()
  ----       resolve("hello")
  ----     end, 1000)
  ----   end)
  ----   local msg = p:await()
  ----   assert.equals("hello", msg)
  ---- end)

end)

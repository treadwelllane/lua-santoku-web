local assert = require("luassert")
local test = require("santoku.test")
local str = require("santoku.string")
local js = require("santoku.web.js")
local val = require("santoku.web.val")

local global = js.global
local Promise = js.Promise

if not str.isempty(os.getenv("TK_WEB_SANITIZE")) then
  print("Skipping async tests when TK_WEB_SANITIZE is set.")
  return
end

collectgarbage("stop")

test("async code", function ()

  test("setTimeout", function ()
    local setTimeout = val.global("setTimeout")
    setTimeout:call(nil, function (_, a, b)
      assert.equals("hello", a)
      assert.equals("world", b)
    end, 0, "hello", "world")
  end)

  test("win:setTimeout", function ()
    local win = val.global("global"):lua()
    win:setTimeout(function (_, a, b)
      assert.equals("hello", a)
      assert.equals("world", b)
    end, 0, "hello", "world")
  end)

  test("promise", function ()
    local Promise = val.global("Promise")
    local p = Promise:new(function (this, resolve)
      resolve(this, "hello")
    end)
    local thn = p:get("then")
    thn:call(p, function (_, msg)
      assert.equals("hello", msg)
    end)
  end)

  test("promise :lua()", function ()
    local Promise = val.global("Promise")
    local p = Promise:new(function (this, resolve)
      resolve(this, "hello")
    end):lua()
    p["then"](p, function (_, msg)
      assert.equals("hello", msg)
    end)
  end)

  test("promise rejection", function ()
    Promise:new(function (this, _, reject)
      reject(this, "test")
    end):await(function (_, ok, err)
      assert.equals(false, ok)
      assert.equals("test", err)
    end)
  end)

  test("promise lua exception", function ()
    Promise:new(function ()
      error("test", 0)
    end):await(function (_, ok, err)
      assert.equals(false, ok)
      assert.equals("test", err)
    end)
  end)

  test("promise resolve", function ()
    Promise:resolve(10):await(function (_, ok, res)
      assert.equals(true, ok)
      assert.equals(10, res)
    end)
  end)

  test("promise reject", function ()
    Promise:reject("failed"):await(function (_, ok, err)
      assert.equals(false, ok)
      assert.equals("failed", err)
    end)
  end)

  test("promise js exception", function ()
    Promise:new(function ()
      global:eval("throw 'test'")
    end):await(function (_, ok, err)
      assert.equals(false, ok)
      assert.equals("test", err)
    end)
  end)

  -- TODO: Get this to work
  -- -- TODO: Even though the error is an unhandled
  -- -- rejection, the error is not caught unless
  -- -- the uncaughtException handler is also
  -- -- registered. Why is this?
  -- test("promise error in handler", function ()
  --   local unhandled = nil
  --   js.process:on("uncaughtException", function () end)
  --   js.process:on("unhandledRejection", function (_, err)
  --     unhandled = err
  --   end)
  --   Promise:reject("failed"):await(function (_, ok, err)
  --     assert.equals("failed", err)
  --     error(err)
  --   end)
  --   global:setTimeout(function ()
  --     assert.equals("failed", unhandled)
  --   end, 100)
  -- end)

  -- TODO: Get this to work
  -- test("js error in js invoked callback", function ()
  --   local unhandled = nil
  --   js.process:on("unhandledRejection", function () end)
  --   js.process:on("uncaughtException", function (_, err)
  --     print("> uncaught", err)
  --     unhandled = err
  --   end)
  --   global:setTimeout(function ()
  --     -- global:eval("throw 'hi'")
  --     error("hi")
  --   end)
  --   -- global:setTimeout(function ()
  --   --   print("x")
  --   --   assert.equals("hi", unhandled)
  --   -- end, 1000)
  -- end)

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

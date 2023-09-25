local assert = require("luassert")
local test = require("santoku.test")
local js = require("santoku.web.js")
local val = require("santoku.web.val")

local global = js.global
local Promise = js.Promise

if os.getenv("SANITIZE") ~= "0" then
  print("Skipping async tests when sanitizer is active.")
  print("Re-run with SANITIZER=0 to run async tests")
  return
end

test("async code", function ()

  test("setTimeout", function ()
    local setTimeout = val.global("setTimeout")
    setTimeout:call(nil, function (this, a, b)
      assert.equals("hello", a)
      assert.equals("world", b)
    end, 0, "hello", "world")
  end)

  test("win:setTimeout", function ()
    local win = val.global("global"):lua()
    win:setTimeout(function (this, a, b, ...)
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
    thn:call(p, function (this, msg)
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
      error("test")
    end):await(function (_, ok, err)
      assert.equals(false, ok)
      assert.equals("test", err)
    end)
  end)

  -- TODO: This causes a memory leak. Why?
  test("promise js exception", function ()
    Promise:new(function ()
      js.eval(nil, "throw 'test'")
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

  -- TODO: Even though the error is an unhandled
  -- rejection, the error is not caught unless
  -- the uncaughtException handler is also
  -- registered. Why is this?
  test("promise error in handler", function ()
    local unhandled = nil
    js.process:on("uncaughtException", function () end)
    js.process:on("unhandledRejection", function (_, err)
      unhandled = err
    end)
    Promise:reject("failed"):await(function (_, ok, err)
      assert.equals("failed", err)
      error(err)
    end)
    global:setTimeout(function ()
      assert.equals("failed", unhandled)
    end, 100)
  end)

end)

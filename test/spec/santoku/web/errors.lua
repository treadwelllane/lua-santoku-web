local js = require("santoku.web.js")
local test = require("santoku.test")
local assert = require("luassert")

local global = js.global
local Promise = js.Promise

test("errors", function ()

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

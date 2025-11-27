local test = require("santoku.test")
local str = require("santoku.string")
local js = require("santoku.web.js")
local val = require("santoku.web.val")
local err = require("santoku.error")
local validate = require("santoku.validate")

local assert = err.assert
local eq = validate.isequal

local global = js.global
local Promise = js.Promise

if not str.isempty(os.getenv("TK_WEB_SANITIZE")) then
  print("Skipping async tests when TK_WEB_SANITIZE is set.")
  return
end

collectgarbage("stop")

test("setTimeout", function ()
  local setTimeout = val.global("setTimeout")
  setTimeout:call(nil, function (_, a, b)
    assert(eq("hello", a))
    assert(eq("world", b))
  end, 0, "hello", "world")
end)

test("win:setTimeout", function ()
  local win = val.global("global"):lua()
  win:setTimeout(function (_, a, b)
    assert(eq("hello", a))
    assert(eq("world", b))
  end, 0, "hello", "world")
end)

test("promise", function ()
  local Promise = val.global("Promise")
  local p = Promise:new(function (this, resolve)
    resolve(this, "hello")
  end)
  local thn = p:get("then")
  thn:call(p, function (_, msg)
    assert(eq("hello", msg))
  end)
end)

test("promise :lua()", function ()
  local Promise = val.global("Promise")
  local p = Promise:new(function (this, resolve)
    resolve(this, "hello")
  end):lua()
  p["then"](p, function (_, msg)
    assert(eq("hello", msg))
  end)
end)

test("promise rejection", function ()
  Promise:new(function (this, _, reject)
    reject(this, "test")
  end):await(function (_, ok, err)
    assert(eq(false, ok))
    assert(eq("test", err))
  end)
end)

test("promise lua exception", function ()
  Promise:new(function ()
    error("test", 0)
  end):await(function (_, ok, err)
    assert(eq(false, ok))
    assert(eq("test", err))
  end)
end)

test("promise resolve", function ()
  Promise:resolve(10):await(function (_, ok, res)
    assert(eq(true, ok))
    assert(eq(10, res))
  end)
end)

test("promise reject", function ()
  Promise:reject("failed"):await(function (_, ok, err)
    assert(eq(false, ok))
    assert(eq("failed", err))
  end)
end)

test("promise js exception", function ()
  Promise:new(function ()
    global:eval("throw 'test'")
  end):await(function (_, ok, err)
    assert(eq(false, ok))
    assert(eq("test", err))
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
--   -- end, 250)
-- end)

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

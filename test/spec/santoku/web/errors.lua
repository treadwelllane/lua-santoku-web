local js = require("santoku.web.js")
local test = require("santoku.test")
local assert = require("luassert")

local global = js.global
local process = js.process
local Promise = js.Promise

-- TODO: When javascript calls lua, and lua
-- throws an error, that error should be
-- catchable in javascript

test("errors", function ()

  test("promise", function ()
    Promise:new(function (_, res, rej)
      error("test")
    end):await(function (_, ok, err)
      assert.equals(false, ok)
      assert.equals("test", err)
    end)
  end)

  -- test("setTimeout", function ()
  --   local called = false
  --   process:on("uncaughtException", function (_, e)
  --     called = true
  --     assert.equals("test", e)
  --   end)
  --   global:setTimeout(function ()
  --     error("test")
  --   end)
  --   global:setTimeout(function ()
  --     assert.equals(true, called)
  --   end)
  -- end)

end)

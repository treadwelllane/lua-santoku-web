local test = require("santoku.test")
local val = require("santoku.web.val")
local err = require("santoku.error")
local validate = require("santoku.validate")

local assert = err.assert
local eq = validate.isequal

collectgarbage("stop")

test("object get str", function ()
  local o = val({ a = 10 })
  assert(eq(10, o:get("a"):lua()))
end)

test("object get num", function ()
  local o = val({ [1] = 1 })
  assert(eq(1, o:get(0):lua()))
end)

test("object construct", function ()
  local obj = val.global("Object"):call(nil)
  assert(eq("object", obj:typeof():lua()))
end)

test("throw lua string error", function ()
  val.global("eval"):call(nil, [[
    function test_throw_string () {
      throw 'string error';
    }
  ]])
  local ok, err = pcall(function ()
    val.global("test_throw_string"):call(nil)
  end)
  assert(eq(false, ok))
  assert(eq("string error", err))
end)

test("exposing a function to javascript", function ()
  local o = val.global("Object"):call(nil)
  o:set("fn", function () end)
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

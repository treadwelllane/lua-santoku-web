local err = require("santoku.error")
local validate = require("santoku.validate")
local test = require("santoku.test")
local val = require("santoku.web.val")

local assert = err.assert
local eq = validate.isequal

collectgarbage("stop")

test("global", function ()
  local vDate = val.global("Date")
  local _ = vDate:lua()
end)

test("val string to uint8array", function ()
  local _ = val.bytes("ABC")
end)

test("object set/get", function ()
  local obj = val.global("Object"):call(nil)
  obj:set("a", 1)
  local one = obj:get("a")
  assert(eq("number", one:typeof():lua()))
  assert(eq(1, one:lua()))
end)

test("array keys", function ()
  local vObject = val.global("Object")
  local Object = vObject:lua()
  local _ = Object.keys
end)

test("basic val", function ()
  local _ = val({ 1, 2, 3, 4, 5 })
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

local assert = require("luassert")
local test = require("santoku.test")
local val = require("santoku.web.val")

collectgarbage("stop")

test("garbage", function ()

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
    assert.equals("number", one:typeof():lua())
    assert.equals(1, one:lua())
  end)

  test("array keys", function ()
    local vObject = val.global("Object")
    local Object = vObject:lua()
    local _ = Object.keys
  end)

  test("basic val", function ()
    local _ = val({ 1, 2, 3, 4, 5 })
  end)

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
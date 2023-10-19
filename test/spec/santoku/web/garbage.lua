local assert = require("luassert")
local test = require("santoku.test")
local str = require("santoku.string")
local val = require("santoku.web.val")

collectgarbage("stop")

test("garbage", function ()

  test("global", function ()
    local vDate = val.global("Date")
    local Date = vDate:lua()
  end)

  test("val string to uint8array", function ()
    local b = val.bytes("ABC")
  end)

  test("object set/get", function ()
    local obj = val.global("Object"):call(nil)
    obj:set("a", 1)
    local one = obj:get("a")
    assert.equals("number", one:typeof():lua())
    assert.equals(1, one:lua())
  end)

  test("array keys", function ()
    local t = { 1, 2, 3, 4, 5 }
    local vObject = val.global("Object")
    local Object = vObject:lua()
    local keys = Object.keys
  end)

  test("basic val", function ()
    local a = val({ 1, 2, 3, 4, 5 })
  end)

end)

collectgarbage("collect")
val.global("gc"):call(nil)

val.global("setTimeout", function ()

  local cntt = 0
  for k, v in pairs(val.IDX_REF_TBL) do
    -- print(k, v)
    cntt = cntt + 1
  end

  -- print("IDX_REF_TBL:", cntt)

  assert.equals(0, cntt, "IDX_REF_TBL not clean")

end, 5000)

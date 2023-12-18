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

collectgarbage("collect")
val.global("gc"):call(nil)

val.global("setTimeout", function ()

  local cntt = 0
  for k, v in pairs(val.IDX_REF_TBL) do
    print(k, v)
    cntt = cntt + 1
  end

  assert.equals(0, cntt, "IDX_REF_TBL not clean")

end, 5000)

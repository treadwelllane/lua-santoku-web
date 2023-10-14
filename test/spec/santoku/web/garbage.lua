local assert = require("luassert")
local test = require("santoku.test")
local str = require("santoku.string")
local val = require("santoku.web.val")

collectgarbage("stop")

test("val", function ()

  test("global", function ()
    local vDate = val.global("Date")
    local Date = vDate:lua()
  end)

  test("val string to uint8array", function ()
    local b = val.bytes("ABC")
  end)

  test("array keys", function ()
    local t = { 1, 2, 3, 4, 5 }
    local vObject = val.global("Object")
    local Object = vObject:lua()
    local keys = Object.keys
  end)

end)

collectgarbage("collect")
collectgarbage("collect")

local cnt = 0
for k, v in pairs(val.IDX_TBL_VAL) do
  -- print(k, v)
  cnt = cnt + 1
end

-- print("IDX_TBL_VAL:", cnt)
-- print("IDX_VAL_REF:", val.IDX_VAL_REF.size)

assert.equals(1, cnt, "IDX_TBL_VAL not clean")
assert.equals(1, val.IDX_VAL_REF.size, "IDX_VAL_REF not clean")

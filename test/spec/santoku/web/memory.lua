-- Base cases that could trigger memory leaks

local assert = require("luassert")
local test = require("santoku.test")
local val = require("santoku.web.val")

collectgarbage("stop")

test("memory", function ()

  test("object get str", function ()
    local o = val({ a = 1 })
    assert.equals(1, o:get("a"):lua())
  end)

  test("object get num", function ()
    local o = val({ [1] = 1 })
    assert.equals(1, o:get(0):lua())
  end)

  test("object construct", function ()
    local obj = val.global("Object"):call(nil)
    assert.equals("object", obj:typeof():lua())
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
    assert.equals(false, ok)
    assert.equals("string error", err)
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

local assert = require("luassert")
local test = require("santoku.test")
local val = require("santoku.web.val")

if os.getenv("EMSCRIPTEN") == "1" or os.getenv("SANITIZE") ~= "0" then
  print("Skipping garbage-async tests when EMSCRIPTEN = 1 or SANITIZE ~= 0")
  print("Re-run with EMSCRIPTEN=0 SANITIZE=0 to run garbage-async tests")
  return
end

collectgarbage("stop")

local setTimeout = val.global("setTimeout")
local gc = val.global("gc")

collectgarbage("collect")
gc:call(nil)

test("val", function ()
  test("callback after garbage", function ()
    local ok, err = pcall(function ()
      setTimeout:call(nil, function () end, 1000)
    end)
    assert(ok, err and err.message)
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

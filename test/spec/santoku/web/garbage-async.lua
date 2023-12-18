local assert = require("luassert")
local test = require("santoku.test")
local str = require("santoku.string")
local val = require("santoku.web.val")

if not str.isempty(os.getenv("TK_WEB_SANITIZE")) then
  print("Skipping garbage-async tests when TK_WEB_SANITIZE is set")
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
      setTimeout:call(nil, function ()
      end, 2000)
    end)
    assert(ok, err and err.message)
  end)
end)

collectgarbage("collect")
val.global("gc"):call(nil)

val.global("setTimeout", function ()

  local cntt = 0
  for _ in pairs(val.IDX_REF_TBL) do
    cntt = cntt + 1
  end

  assert.equals(0, cntt, "IDX_REF_TBL not clean")

end, 5000)

local assert = require("luassert")
local test = require("santoku.test")
local str = require("santoku.string")
local val = require("santoku.web.val")

if not str.isempty(os.getenv("TK_WEB_SANITIZE")) then
  print("Skipping garbage-async tests when TK_WEB_SANITIZE is set")
  return
end

collectgarbage("stop")

test("val", function ()
  test("callback after garbage", function ()
    local ok, err = pcall(function ()
      val.global("setTimeout"):call(nil, function ()
      end, 250)
    end)
    assert(ok, err and err.message)
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

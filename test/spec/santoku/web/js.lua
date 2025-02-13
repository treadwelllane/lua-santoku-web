local test = require("santoku.test")
local err = require("santoku.error")
local validate = require("santoku.validate")
local tbl = require("santoku.table")
local val = require("santoku.web.val")
local js = require("santoku.web.js")

local teq = tbl.equals
local assert = err.assert
local eq = validate.isequal

collectgarbage("stop")

test("equality", function ()
  local c0 = js.console
  local c1 = js.console
  assert(eq(c0:val(), c1:val()))
end)

test("object to lua", function ()
  local o0 = js.Object:new()
  local o1 = js.Object:new()
  local o2 = js.Array:new()
  o0.o = o1
  o1.a = 1
  o1.b = o2
  o2:push(1)
  o2:push(2)
  o2:push(3)
  local t = o0:val():lua(true)
  assert(teq({ o = { a = 1, b = { 1, 2, 3 } } }, t))
end)

test("object to lua via val.lua()", function ()
  local o0 = js.Object:new()
  local o1 = js.Object:new()
  local o2 = js.Array:new()
  o0.o = o1
  o1.a = 1
  o1.b = o2
  o2:push(1)
  o2:push(2)
  o2:push(3)
  local t = val.lua(o0, true)
  assert(teq({ o = { a = 1, b = { 1, 2, 3 } } }, t))
end)

test("number to lua via val.lua()", function ()
  assert(teq({ 1 }, { val.lua(1, true) }))
  assert(teq({ 1 }, { val.lua(1) }))
end)

test("date gettime", function ()
  local t = 1652745600000
  assert(eq(js.Date:new(t):getTime(), t))
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

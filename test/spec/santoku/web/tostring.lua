local test = require("santoku.test")
local err = require("santoku.error")
local tbl = require("santoku.table")
local js = require("santoku.web.js")

local teq = tbl.equals
local assert = err.assert

collectgarbage("stop")

test("error tostring", function ()
  local e = js.Error:new("Some error")
  assert(teq({ "Error: Some error" }, { tostring(e) }))
end)

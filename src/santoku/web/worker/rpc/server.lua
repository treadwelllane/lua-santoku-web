local js = require("santoku.web.js")
local val = require("santoku.web.val")
local compat = require("santoku.compat")

local global = js.self

local M = {}

M.init = function (obj)
  global:addEventListener("message", function (_, ev)
    local ch = ev.ports[0]
    local fn = ev.data[0]
    local args = ev.data:slice(1)
    local out = val.array(obj[fn](compat.unpack(args)))
    ch:postMessage(out)
  end)
end

return M

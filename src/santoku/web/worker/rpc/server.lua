local val = require("santoku.web.val")
local compat = require("santoku.compat")

local M = {}

M.init = function (obj, on_message)
  on_message(function (ev)
    local ch = ev.ports[1]
    local fn = ev.data[1]
    local args = ev.data:slice(1)
    local out = val({ obj[fn](compat.unpack(args)) }, true)
    ch:postMessage(out)
  end)
end

return M

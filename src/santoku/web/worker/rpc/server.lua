local val = require("santoku.web.val")
local compat = require("santoku.compat")

local M = {}

M.init = function (obj, on_message)
  return on_message(function (ev)
    local ch = ev.ports[1]
    local key = ev.data[1]
    local args = ev.data:slice(1)
    if obj.async and obj.async[key] then
      args:push(function (...)
        return ch:postMessage(val({ ... }, true))
      end)
      return obj.async[key](compat.unpack(args))
    elseif obj[key] then
      return ch:postMessage(val({ obj[key](compat.unpack(args)) }, true))
    else
      return ch:postMessage(val({ false, "Property '" .. tostring(key) .. "' not found" }, true))
    end
  end)
end

return M

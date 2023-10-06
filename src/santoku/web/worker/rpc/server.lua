local val = require("santoku.web.val")
local compat = require("santoku.compat")

local M = {}

M.init = function (obj, on_message)
  return on_message(function (ev)
    local port = ev.data[2]
    local key = ev.data[1]
    local args = ev.data:slice(2)
    if obj.async and obj.async[key] then
      args:push(function (...)
        return port:postMessage(val({ ... }, true))
      end)
      return obj.async[key](compat.unpack(args))
    elseif obj[key] then
      return port:postMessage(val({ obj[key](compat.unpack(args)) }, true))
    else
      return port:postMessage(val({ false, "Property '" .. tostring(key) .. "' not found" }, true))
    end
  end)
end

return M

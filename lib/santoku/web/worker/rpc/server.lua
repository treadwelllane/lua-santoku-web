local val = require("santoku.web.val")
local err = require("santoku.error")
local arr = require("santoku.array")

local M = {}

M.init = function (obj, on_message)
  return on_message(function (ev)
    local port = ev.data[2]
    local key = ev.data[1]
    local args = {}
    for i = 3, ev.data.length do
      args[#args + 1] = ev.data[i]
    end
    if obj.async and obj.async[key] then
      arr.push(args, function (...)
        return port:postMessage(val({ ... }, true))
      end)
      return err.pcall(obj.async[key], arr.spread(args))
    elseif obj[key] then
      return port:postMessage(val({ err.pcall(obj[key], arr.spread(args)) }, true))
    else
      return port:postMessage(val({ false, "Property '" .. tostring(key) .. "' not found" }, true))
    end
  end)
end

return M

local js = require("santoku.web.js")
local val = require("santoku.web.val")
local tup = require("santoku.tuple")
local compat = require("santoku.compat")

local Worker = js.Worker
local MessageChannel = js.MessageChannel

local M = {}

M.init = function (fp, callback)
  local ok, worker = pcall(Worker.new, Worker, fp)
  if not ok then
    callback(false, worker)
  else
    callback(true, setmetatable({}, {
      __index = function (_, k)
        return function (...)
          local mc = MessageChannel:new()
          local n = tup.len(...)
          -- TODO: Consider await or similar
          -- structure instead of expecting a
          -- callback as the last function
          -- argument, which might be confusing.
          local callback = tup.get(n, ...)
          local args = val({ k, tup.take(n - 1, ...) }, true)
          worker:postMessage(args, { mc.port2 })
          mc.port1.onmessage = function (_, ev)
            callback(compat.unpack(ev.data))
          end
        end
      end
    }), worker)
  end
end

return M

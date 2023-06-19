local js = require("santoku.web.js")
local val = require("santoku.web.val")
local tup = require("santoku.tuple")

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
          local callback = tup.get(n, ...)
          local args = val.array()
          -- TODO: santoku web should expose
          -- helper function to convert to js,
          -- or at least allow structured clones
          -- of proxy objects
          args:set(0, k)
          for i = 1, n - 1 do
            args:set(i, tup.get(i, ...))
          end
          worker:postMessage(args, { mc.port2 })
          mc.port1.onmessage = function (_, ev)
            callback(ev.data)
          end
        end
      end
    }))
  end
end

return M

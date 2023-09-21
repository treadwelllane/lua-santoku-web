local js = require("santoku.web.js")
local val = require("santoku.web.val")
local err = require("santoku.err")
local tup = require("santoku.tuple")
local compat = require("santoku.compat")

local Promise = js.Promise
local Worker = js.Worker
local MessageChannel = js.MessageChannel

local M = {}

M.init = function (fp)
  return err.pwrap(function (check)
    local worker = check(pcall(Worker.new, Worker, fp))
    return setmetatable({}, {
      __index = function (_, k)
        -- TODO: get await working with this
        return function (...)
          local args = tup(...)
          return err.pwrap(function (check)
            local ret = check(Promise:new(function (this, resolve)
              local mc = MessageChannel:new()
              local args = val({ k, args() }, true)
              worker:postMessage(args, { mc.port2 })
              mc.port1.onmessage = function (_, ev)
                resolve(this, ev.data)
              end
            end):await())
            return compat.unpack(ret)
          end)
        end
      end
    }), worker
  end)
end

return M

local js = require("santoku.web.js")
local val = require("santoku.web.val")
local arr = require("santoku.array")
local util = require("santoku.web.util")

local Worker = js.Worker
local MessageChannel = js.MessageChannel

local M = {}

local transferables = {
  ArrayBuffer = true,
  MessagePort = true,
  ReadableStream = true,
  WritableStream = true,
  TransformStream = true,
  WebTransportReceiveStream = true,
  AudioData = true,
  ImageBitmap = true,
  VideoFrame = true,
  OffscreenCanvas = true,
  RTCDataChannel = true
}

M.init = function (fp)
  local worker = Worker:new(fp)
  local port = M.create_port(worker)
  return M.init_port(port), worker
end

M.create_port = function (worker)
  local ch = MessageChannel:new()
  M.register_port(worker, ch.port2)
  return ch.port1
end

M.register_port = function (worker, port)
  worker:postMessage(val({ REGISTER_PORT = port }, true), { port })
end

M.init_port = function (port)
  return setmetatable({}, {
    __index = function (_, k)
      return function (...)
        local args = { ... }

        local tfrs = arr.filtered(args, function (t)
          local ok, name = pcall(function ()
            return t.constructor.name
          end)
          return ok and transferables[name]
        end)

        local _, result = util.promise(function (complete)
          local ch = MessageChannel:new()
          port:postMessage(
            val({ k, ch.port2, arr.spread(args) }, true),
            { ch.port2, arr.spread(tfrs) })
          ch.port1.onmessage = function (_, ev)
            complete(true, ev.data)
          end
          ch.port1:start()
        end):await()
        return arr.spread(val.lua(result, true))
      end
    end
  })
end

return M

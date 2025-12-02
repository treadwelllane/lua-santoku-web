local js = require("santoku.web.js")
local val = require("santoku.web.val")
local arr = require("santoku.array")
local varg = require("santoku.varg")
local it = require("santoku.iter")

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
  print("wrpc.init spawning worker:", fp)
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

        local ch = MessageChannel:new()
        local n = varg.len(...)
        local callback = varg.get(n, ...)

        local args = { varg.take(n - 1, ...) }

        local tfrs = it.collect(it.filter(function (t)
          local ok, n = pcall(function ()
            return t.constructor.name
          end)
          return ok and transferables[n]
        end, it.ivals(args)))

        -- TODO: currently this only supports
        -- transferables that occur at the top-level of
        -- arguments, not nested within objects and
        -- tables. Ideally, the val(..., true)
        -- traversal could optionally return a table of
        -- all transferables encountered.
        port:postMessage(
          val({ k, ch.port2, arr.spread(args) }, true),
          { ch.port2, arr.spread(tfrs) })

        ch.port1.onmessage = function (_, ev)
          local args = {}
          for i = 1, ev.data.length do
            args[#args + 1] = ev.data[i]
          end
          callback(arr.spread(args))
        end

      end
    end
  })
end

return M

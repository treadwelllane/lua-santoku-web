local js = require("santoku.web.js")
local val = require("santoku.web.val")
local err = require("santoku.err")
local gen = require("santoku.gen")
local tup = require("santoku.tuple")
local compat = require("santoku.compat")

local Worker = js.Worker
local MessageChannel = js.MessageChannel

local M = {}

local transferables = gen.pack(
  "ArrayBuffer",
  "MessagePort",
  "ReadableStream",
  "WritableStream",
  "TransformStream",
  "WebTransportReceiveStream",
  "AudioData",
  "ImageBitmap",
  "VideoFrame",
  "OffscreenCanvas",
  "RTCDataChannel"
):set()

M.init = function (fp)
  return err.pwrap(function (check)
    local worker = check(pcall(Worker.new, Worker, fp))
    local port = M.create_port(worker)
    return M.init_port(port), worker
  end)
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
        local n = tup.len(...)
        local callback = tup.get(n, ...)

        local args = tup(tup.take(n - 1, ...))

        local tfrs = tup(tup.filter(function (t)
          local ok, n = pcall(function ()
            return t.constructor.name
          end)
          return ok and transferables[n]
        end, args()))

        -- TODO: currently this only supports
        -- transferables that occur at the top-level of
        -- arguments, not nested within objects and
        -- tables. Ideally, the val(..., true)
        -- traversal could optionally return a table of
        -- all transferables encountered.
        port:postMessage(
          val({ k, ch.port2, args() }, true),
          { ch.port2, tfrs() })

        ch.port1.onmessage = function (_, ev)
          callback(compat.unpack(ev.data))
        end

      end
    end
  })
end

return M

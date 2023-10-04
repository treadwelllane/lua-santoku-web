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

-- TODO: currently this only supports
-- transferables that occur at the top-level of
-- arguments, not nested within objects and
-- tables. Ideally, the val(..., true)
-- traversal could optionally return a table of
-- all transferables encountered.
M.init = function (fp)
  return err.pwrap(function (check)

    local worker = check(pcall(Worker.new, Worker, fp))

    return setmetatable({}, {
      __index = function (_, k)
        return function (...)

          local mc = MessageChannel:new()
          local n = tup.len(...)
          local callback = tup.get(n, ...)

          local args = tup(tup.take(n - 1, ...))

          local tfrs = tup(tup.filter(function (t)
            local ok, n = pcall(function ()
              return t.constructor.name
            end)
            return ok and transferables[n]
          end, args()))

          worker:postMessage(
            val({ k, args() }, true),
            { mc.port2, tfrs() })

          mc.port1.onmessage = function (_, ev)
            callback(compat.unpack(ev.data))
          end

        end
      end
    }), worker

  end)
end

return M

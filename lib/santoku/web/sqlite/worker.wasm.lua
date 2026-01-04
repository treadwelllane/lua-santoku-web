local js = require("santoku.web.js")
local val = require("santoku.web.val")
local sqlite = require("santoku.web.sqlite")
local wrpc = require("santoku.web.worker.rpc.server")
local async = require("santoku.web.async")

local global = js.self
local Module = global.Module

return function (db_path, opts, handler)
  if type(opts) == "function" then
    handler = opts
    opts = nil
  end

  local verbose = opts and opts.verbose
  if verbose then print("[sqlite-worker] function called, db_path:", db_path) end

  async(function ()
    if verbose then print("[sqlite-worker] async block started") end
    if verbose then print("[sqlite-worker] starting sqlite.open") end
    local ok, db = sqlite.open(db_path, opts)
    if verbose then print("[sqlite-worker] sqlite.open returned:", ok) end
    if not ok then
      global:postMessage(val({ type = "db_error", error = tostring(db) }, true))
      return
    end
    if verbose then print("[sqlite-worker] calling handler") end
    local ok2, handlers = handler(ok, db)
    if verbose then print("[sqlite-worker] handler returned:", ok2) end
    if not ok2 then
      global:postMessage(val({ type = "db_error", error = "handler returned false: " .. tostring(handlers) }, true))
      return
    end
    if verbose then print("[sqlite-worker] calling wrpc.init") end
    local rpc_handler = wrpc.init(handlers)
    if verbose then print("[sqlite-worker] setting up Module.on_message") end
    Module.on_message = function (_, ev)
      if ev.data and ev.data.REGISTER_PORT then
        if verbose then print("[sqlite-worker] REGISTER_PORT received") end
        ev.data.REGISTER_PORT.onmessage = function (_, port_ev)
          if port_ev.data and port_ev.data.type == "ping" then
            local pong_port = port_ev.ports and port_ev.ports[1]
            if pong_port then
              if verbose then print("[sqlite-worker] ping received, sending pong") end
              pong_port:postMessage(val({ type = "pong" }, true))
            end
            return
          end
          if verbose then print("[sqlite-worker] port message received:", port_ev.data and port_ev.data[1]) end
          return rpc_handler(port_ev)
        end
      end
    end
    if verbose then print("[sqlite-worker] calling Module:start()") end
    Module:start()
    if verbose then print("[sqlite-worker] Module:start() complete") end
  end)
end

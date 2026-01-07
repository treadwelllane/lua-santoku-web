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

  local rpc_handler = nil
  local pending_ports = {}

  local first_port_ready = false

  Module.on_message = function (_, ev)
    if ev.data and ev.data.REGISTER_PORT then
      if verbose then print("[sqlite-worker] REGISTER_PORT received") end
      local port = ev.data.REGISTER_PORT
      port.onmessage = function (_, port_ev)
        if port_ev.data and port_ev.data.type == "ping" then
          local pong_port = port_ev.ports and port_ev.ports[1]
          if pong_port then
            if verbose then print("[sqlite-worker] ping received, sending pong") end
            pong_port:postMessage(val({ type = "pong" }, true))
          end
          return
        end
        if rpc_handler then
          if verbose then print("[sqlite-worker] port message received:", port_ev.data and port_ev.data[1]) end
          return rpc_handler(port_ev)
        else
          if verbose then print("[sqlite-worker] queuing message, db not ready yet") end
          pending_ports[#pending_ports + 1] = port_ev
        end
      end
      if verbose then print("[sqlite-worker] Sending port_ready through port") end
      port:postMessage(val({ type = "port_ready" }, true))
      if not first_port_ready then
        first_port_ready = true
        if verbose then print("[sqlite-worker] First port registered, signaling worker_ready") end
        global:postMessage(val({ type = "worker_ready" }, true))
      end
    end
  end
  if verbose then print("[sqlite-worker] message handler set up early") end
  Module:start()
  if verbose then print("[sqlite-worker] Module:start() complete") end

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
    rpc_handler = wrpc.init(handlers)
    if verbose then print("[sqlite-worker] processing", #pending_ports, "queued messages") end
    for i = 1, #pending_ports do
      rpc_handler(pending_ports[i])
    end
    pending_ports = {}
    if verbose then print("[sqlite-worker] worker fully initialized") end
  end)
end

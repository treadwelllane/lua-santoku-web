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

  local rpc_handler = nil
  local pending_ports = {}

  Module.on_message = function (_, ev)
    if ev.data and ev.data.REGISTER_PORT then
      local port = ev.data.REGISTER_PORT
      if rpc_handler then
        port.onmessage = function (_, port_ev)
          return rpc_handler(port_ev)
        end
      else
        pending_ports[#pending_ports + 1] = port
      end
    end
  end

  Module:start()

  async(function ()
    local ok, db = sqlite.open(db_path, opts)
    if not ok then
      global:postMessage(val({ type = "db_error", error = tostring(db) }, true))
      return
    end
    local ok2, handlers = handler(ok, db)
    if not ok2 then
      return
    end
    rpc_handler = wrpc.init(handlers)
    for _, port in ipairs(pending_ports) do
      port.onmessage = function (_, port_ev)
        return rpc_handler(port_ev)
      end
    end
    pending_ports = {}
  end)
end

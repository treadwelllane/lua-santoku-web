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
    local rpc_handler = wrpc.init(handlers)
    Module.on_message = function (_, ev)
      if ev.data and ev.data.REGISTER_PORT then
        ev.data.REGISTER_PORT.onmessage = function (_, port_ev)
          return rpc_handler(port_ev)
        end
      end
    end
    return Module:start()
  end)
end

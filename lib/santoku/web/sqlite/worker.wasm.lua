local js = require("santoku.web.js")
local sqlite = require("santoku.web.sqlite")
local wrpc = require("santoku.web.worker.rpc.server")

local global = js.self
local Module = global.Module

return function (db_path, opts, handler)
  if type(opts) == "function" then
    handler = opts
    opts = nil
  end

  return sqlite.open(db_path, opts, function (ok, db)
    return handler(ok, db, function (ok2, handlers)
      if not ok2 then
        return
      end
      return wrpc.init(handlers, function (rpc_handler)
        Module.on_message = function (_, ev)
          if ev.data and ev.data.REGISTER_PORT then
            ev.data.REGISTER_PORT.onmessage = function (_, port_ev)
              return rpc_handler(port_ev)
            end
          end
        end
        return Module:start()
      end)
    end)
  end)
end

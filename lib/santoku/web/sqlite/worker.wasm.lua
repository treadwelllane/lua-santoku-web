local js = require("santoku.web.js")
local sqlite = require("santoku.web.sqlite")
local wrpc = require("santoku.web.worker.rpc.server")

local global = js.self
local Module = global.Module

return function (db_path, handler)
  return sqlite.open_opfs(db_path, function (ok, db)
    return handler(ok, db, function (ok, handlers)
      if not ok then
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

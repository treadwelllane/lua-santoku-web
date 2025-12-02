local js = require("santoku.web.js")
local sqlite = require("santoku.web.sqlite")
local wrpc = require("santoku.web.worker.rpc.server")

local global = js.self
local Module = global.Module

local function create_worker (db_path, opts, handler)
  if type(opts) == "function" then
    handler = opts
    opts = {}
  end
  opts = opts or {}

  local open_fn = opts.sahpool and sqlite.open_sahpool or sqlite.open_opfs
  local open_opts = opts.sahpool and opts.sahpool_opts or nil

  local function do_open (callback)
    if open_opts then
      return open_fn(db_path, open_opts, callback)
    else
      return open_fn(db_path, callback)
    end
  end

  return do_open(function (ok, db)
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

return create_worker

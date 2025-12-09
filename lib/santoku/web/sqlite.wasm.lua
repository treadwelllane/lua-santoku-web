local js = require("santoku.web.js")
local val = require("santoku.web.val")
local sqlite = require("santoku.sqlite")
local err = require("santoku.error")
local Object = js.Object

local M = {}

local OK, ERROR, ROW, DONE = 0, 1, 100, 101

local function cast_param (p)
  if type(p) == "table" and p.instanceof and p:instanceof(js.Date) then
    return p:getTime()
  else
    return p
  end
end

local function create_db_wrapper (wsqlite, raw_db)
  return sqlite({

    db = raw_db,

    exec = function (db, sql)
      local ok, e = err.pcall(db.db.exec, db.db, sql)
      if not ok then
        db.err = e
        return ERROR
      else
        db.err = nil
        return OK
      end
    end,

    prepare = function (db, sql)
      local ok, stmt = err.pcall(db.db.prepare, db.db, sql)
      if not ok then
        db.err = stmt
        return nil
      else
        db.err = nil
        return setmetatable({

          bind_names = function (_, t)
            local ok0, e = err.pcall(function ()
              Object:keys(t):forEach(function (_, k)
                local v = t[k]
                stmt:bind(":" .. k, cast_param(v))
              end)
            end)
            if ok0 then
              return OK
            else
              err.error(e)
              return ERROR
            end
          end,

          bind_values = function (_, ...)
            local ok0, e = err.pcall(function (...)
              for i = 1, select("#", ...) do
                stmt:bind(i, cast_param(select(i, ...)))
              end
            end, ...)
            if ok0 then
              return OK
            else
              err.error(e)
              return ERROR
            end
          end,

          step = function ()
            local ok0, res = err.pcall(stmt.step, stmt)
            if not ok0 then
              db.err = res
              return ERROR
            elseif res then
              db.err = nil
              return ROW
            else
              db.err = nil
              return DONE
            end
          end,

          get_named_values = function ()
            local ret = {}
            for i = 0, stmt.columnCount - 1 do
              local k = val.lua(stmt:getColumnName(i))
              local v = val.lua(stmt:get(i))
              ret[k] = v
            end
            return ret
          end,

          reset = function ()
            stmt:reset(true)
            return OK
          end,

          columns = function ()
            return stmt.columnCount
          end,

          get_value = function (_, n)
            return val.lua(stmt:get(n))
          end,

        }, {
          __index = stmt
        })
      end
    end,

    last_insert_rowid = function (db)
      return wsqlite.capi:sqlite3_last_insert_rowid(db.db.pointer)
    end,

    errcode = function (db)
      if db.err then
        return db.err.name
      end
    end,

    errmsg = function (db)
      if db.err then
        return db.err.message
      end
    end,

  })
end

M.open = function (dbfile, opts, callback)
  if type(opts) == "function" then
    callback = opts
    opts = {}
  end
  opts = opts or {}
  local hash_manifest = js.self.HASH_MANIFEST
  if hash_manifest then
    local hashed_wasm = hash_manifest["sqlite3.wasm"]
    if hashed_wasm then
      local sIMS = js.globalThis.sqlite3InitModuleState
      if sIMS and sIMS.urlParams then
        sIMS.urlParams:set("sqlite3.wasm", "/" .. hashed_wasm)
      end
    end
  end
  js:sqlite3InitModule():await(function (_, ok, wsqlite)
    if not ok then
      return callback(false, wsqlite)
    end
    wsqlite:installOpfsSAHPoolVfs(opts):await(function (_, ok2, pool_util)
      if not ok2 then
        return callback(false, pool_util)
      end
      callback(err.pcall(function ()
        local raw_db = pool_util.OpfsSAHPoolDb:new(dbfile)
        return create_db_wrapper(wsqlite, raw_db)
      end))
    end)
  end)
end

return M

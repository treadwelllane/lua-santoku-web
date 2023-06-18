-- In order for this to work, you must build
-- sqlite for wasm and provide emcc this flag:
--    --pre-js /path/to/sqlite/ext/wasm/jswasm/sqlite3.js
--
-- Additionally, neighboring files sqlite3.wasm
-- and sqlite3-opfs-async-proxy.js must be
-- hosted next to the compiled script.

local err = require("santoku.err")
local js = require("santoku.web.js")
local sqlite = require("santoku.sqlite")

local M = {}

local function cast_param (p)
  if p and p.instanceof and p:instanceof(js.Date) then
    return p:getTime()
  else
    return p
  end
end

M.open_opfs = function (dbfile, callback)

  js:sqlite3InitModule():await(function (_, ok, wsqlite)

    if not ok then
      callback(false, wsqlite)
      return
    end

    callback(err.pwrap(function ()

      return sqlite.wrap({

        db = wsqlite.oo1.OpfsDb:new(dbfile),

        exec = function (db, sql)
          local ok, err = pcall(db.db.exec, db.db, sql)
          if not ok then
            db.err = err
            return sqlite.ERROR
          else
            db.err = nil
            return sqlite.OK
          end
        end,

        prepare = function (db, sql)
          local ok, stmt = pcall(db.db.prepare, db.db, sql)
          if not ok then
            db.err = stmt
            return nil
          else
            db.err = nil
            return setmetatable({

              bind_names = function (_, t)
                local ok, err = pcall(function ()
                  for k, v in pairs(t) do
                    -- TODO: sqlite supports
                    -- both ":" and "$", but
                    -- we're hardcoding the
                    -- former. This can be
                    -- solved by querying the
                    -- prepared statement for
                    -- variables and then
                    -- extracting those from the
                    -- table, instead of the
                    -- other way around.
                    stmt:bind(":" .. k, cast_param(v))
                  end
                end)
                if ok then
                  return sqlite.OK
                else
                  -- TODO: not getting caught
                  error(err)
                  return sqlite.ERROR
                end
              end,

              bind_values = function (_, ...)
                local ok, err = pcall(function (...)
                  for i = 1, select("#", ...) do
                    stmt:bind(i, cast_param(select(i, ...)))
                  end
                end, ...)
                if ok then
                  return sqlite.OK
                else
                  -- TODO: not getting caught
                  error(err)
                  return sqlite.ERROR
                end
              end,

              step = function ()
                local ok, res = pcall(stmt.step, stmt)
                if not ok then
                  db.err = res
                  return sqlite.ERROR
                elseif res then
                  db.err = nil
                  return sqlite.ROW
                else
                  db.err = nil
                  return sqlite.DONE
                end
              end,

              get_named_values = function ()
                local ret = {}
                for i = 0, stmt.columnCount - 1 do
                  local k = stmt:getColumnName(i)
                  local v = stmt:get(i)
                  ret[k] = v
                end
                return ret
              end,

              reset = function ()
                stmt:reset(true)
                return sqlite.OK
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

    end))

  end)

end

return M

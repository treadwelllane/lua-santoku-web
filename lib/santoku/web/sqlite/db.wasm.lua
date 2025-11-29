-- High-level SQLite database module for client-side apps
-- Provides server-like DX for defining db accessors
--
-- Usage:
--   return require("santoku.web.sqlite.db").define("myapp.db", migrations, function (db)
--     return {
--       add_item = db.inserter("insert into items (name) values (?)"),
--       get_items = db.all("select * from items"),
--     }
--   end)

local sqlite = require("santoku.web.sqlite")
local migrate = require("santoku.sqlite.migrate")

local M = {}

-- Define a database module with migrations and accessor builder
-- Returns a module with:
--   .init(callback) - Initialize the db, calls callback(ok, db_module)
--   .handlers - Table of handler functions for RPC exposure
M.define = function (db_name, migrations, accessor_builder)
  local mod = {}
  local db_instance = nil
  local accessors = nil

  -- Initialize the database
  mod.init = function (callback)
    if db_instance then
      callback(true, mod)
      return
    end

    sqlite.open_opfs("/" .. db_name, function (ok, db)
      if not ok then
        return callback(false, db)
      end

      -- Run migrations
      migrate(db, migrations)

      db_instance = db

      -- Build accessors using the db
      accessors = accessor_builder(db)

      -- Copy accessors to module for direct access
      for k, v in pairs(accessors) do
        mod[k] = v
      end

      -- Build handlers table for RPC (wraps each accessor)
      mod.handlers = {}
      for k, v in pairs(accessors) do
        if type(v) == "function" then
          mod.handlers[k] = v
        end
      end

      callback(true, mod)
    end)
  end

  -- Expose the raw db for advanced usage
  mod.raw = function ()
    return db_instance
  end

  return mod
end

return M

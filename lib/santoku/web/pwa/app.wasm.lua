-- PWA app entry point
-- Handles initialization of db, SharedService, and main app code
--
-- Usage:
--   require("santoku.web.pwa.app")({
--     name = "myapp",
--     db = require("myapp.db"),  -- optional
--     main = function (db)       -- optional
--       -- app initialization code
--     end
--   })

local shared = require("santoku.web.sqlite.shared")

local M = {}

M.init = function (opts)
  opts = opts or {}

  local name = opts.name or "app"
  local db_module = opts.db
  local main_fn = opts.main

  local service_name = name .. "-db"

  if db_module then
    -- Initialize db and set up SharedService
    db_module.init(function (ok, db)
      if not ok then
        print("Failed to initialize database:", db)
        return
      end

      -- Create SharedService for cross-tab coordination
      local service = shared.SharedService(service_name, function ()
        return shared.create_provider_port(db.handlers, false)
      end)

      -- Activate this tab as potential provider
      service.activate()

      -- Call main function with db access
      if main_fn then
        main_fn(db)
      end
    end)
  else
    -- No db, just call main
    if main_fn then
      main_fn()
    end
  end
end

return M

local js = require("santoku.web.js")
local sah = require("santoku.web.sqlite.sah")
local db_mod = require("santoku.sqlite.db")
local sqlite = require("santoku.sqlite")
local err = require("santoku.error")

local M = {}

M.open = function (dbfile, opts)
  if type(opts) == "function" then
    opts = {}
  end
  opts = opts or {}
  local call_ok, p = pcall(function ()
    return js.globalThis:__tk_sah_pool_init(
      opts.directory or ".opfs-sahpool",
      opts.initialCapacity or 6
    )
  end)
  if not call_ok then return false, tostring(p) end
  local ok, e = p:await()
  if not ok then return false, tostring(e) end
  local reg_ok, reg_err = pcall(sah.register_vfs)
  if not reg_ok then return false, tostring(reg_err) end
  return err.pcall(function ()
    local db = db_mod.open_v2(dbfile, "opfs-sahpool")
    if not db then error("sqlite open_v2 failed: " .. tostring(dbfile)) end
    return sqlite(db)
  end)
end

return M

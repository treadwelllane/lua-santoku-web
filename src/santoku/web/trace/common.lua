-- TODO: Lines corresponding to wrapFetch are
-- commented. See the TODO below for details.
--
-- local gen = require("santoku.gen")
-- local tup = require("santoku.tuple")

local vec = require("santoku.vector")

return function (callback, global, opts)

  opts = opts or {}

  local JSON = global.JSON
  local console = global.console
  -- local Request = global.Request
  -- local Promise = global.Promise

  local oldwinerr = global and global.onerror
  local oldfetch = global and global.fetch
  local logtypes = vec("log", "error")
  local oldlogs = {}
  local oldprint = nil

  local function wrapPrint ()
    oldprint = print
    _G.print = function (...)
      oldprint(...)
      callback(JSON:stringify({
        source = "print",
        args = { ... }
      }))
    end
  end

  local function wrapLog (typ)
    if oldlogs[typ] then
      return
    end
    oldlogs[typ] = console[typ]
    console[typ] = function (_, ...)
      oldlogs.log(console, ...)
      callback(JSON:stringify({
        source = "console",
        typ, args = { ... }
      }))
    end
  end

  local function wrapLogs ()
    logtypes:each(function(lt)
      wrapLog(lt)
    end)
  end

  local function onErr (ev)
    callback(JSON:stringify({
      source = "error",
      event = ev,
      name = ev and ev.name,
      message = ev and ev.message,
    }))
    if oldwinerr then
      oldwinerr(console, ev)
    end
  end

  local function wrapErr ()
    if global then
      global:addEventListener("error", function (_, ev)
        onErr(ev)
      end)
    end
  end

  -- TODO: This is causing failures loading
  -- sqlite and eruda
  --
  -- local function wrapFetch ()
  --   if global and oldfetch then
  --     global.fetch = function (thisfetch, r, ...)
  --       local args = tup(...)
  --       local req
  --       if type(r) == "string" or not r:instanceof(Request) then
  --         req = Request:new(r, args())
  --       else
  --         req = r:clone()
  --       end
  --       return Promise:new(function (thisp, resolve)
  --         req:text():await(function (_, ok, body)
  --           assert(ok)
  --           callback(JSON:stringify({
  --             source = "fetch",
  --             request = {
  --               url = req.url,
  --               method = req.method,
  --               body = body,
  --               headers = { gen.ivals(req.headers):unpack() }
  --             }
  --           }))
  --           oldfetch(thisfetch, r, args()):await(function(_, ok, resp)
  --             assert(ok)
  --             local clone = resp:clone()
  --             return clone:text():await(function (_, ok, body)
  --               assert(ok)
  --               callback(JSON:stringify({
  --                 source = "fetch",
  --                 response = {
  --                   url = clone.url,
  --                   method = clone.method,
  --                   status = clone.status,
  --                   body = body,
  --                   headers = { gen.ivals(clone.headers):unpack() },
  --                 }
  --               }))
  --               resolve(thisp, resp)
  --             end)
  --           end)
  --         end)
  --       end)
  --     end
  --   end
  -- end

  if opts.print ~= false then
    wrapPrint()
  end

  if opts.error ~= false then
    wrapErr()
  end

  if opts.logs ~= false then
    wrapLogs()
  end

  -- TODO: see above
  -- if opts.fetch ~= false then
  --   wrapFetch()
  -- end

  return {
    oldlogs = oldlogs,
    oldwinerr = oldwinerr,
    oldfetch = oldfetch,
    onErr = onErr
  }

end

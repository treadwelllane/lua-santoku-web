local gen = require("santoku.gen")
local vec = require("santoku.vector")
local tup = require("santoku.tuple")

return function (callback, global)

  local JSON = global.JSON
  local console = global.console
  local Request = global.Request
  local Promise = global.Promise

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

  local function wrapErr ()
    if global then
      global:addEventListener("error", function (_, ev)
        callback(JSON:stringify({
          source = "error",
          event = ev,
          name = ev.name,
          message = ev.message,
        }))
        if oldwinerr then
          oldwinerr(console, ev)
        end
      end)
    end
  end

  local function wrapFetch ()
    if global and oldfetch then
      global.fetch = function (_, r, ...)
        local args = tup(...)
        local req
        if type(r) == "string" or not r:instanceof(Request) then
          req = Request:new(r, args())
        else
          req = r:clone()
        end
        return Promise:new(function (this, resolve)
          req:text():await(function (_, ok, body)
            assert(ok)
            callback(JSON:stringify({
              source = "fetch",
              request = {
                url = req.url,
                method = req.method,
                body = body,
                headers = { gen.ivals(req.headers):unpack() }
              }
            }))
            oldfetch(global, r, args()):await(function(_, ok, resp)
              assert(ok)
              local clone = resp:clone()
              return clone:text():await(function (_, ok, body)
                assert(ok)
                callback(JSON:stringify({
                  source = "fetch",
                  response = {
                    url = clone.url,
                    method = clone.method,
                    status = clone.status,
                    body = body,
                    headers = { gen.ivals(clone.headers):unpack() },
                  }
                }))
                resolve(this, resp)
              end)
            end)
          end)
        end)
      end
    end
  end

  wrapPrint()
  wrapErr()
  wrapLogs()
  wrapFetch()

  return { oldlogs = oldlogs, oldwinerr = oldwinerr, oldfetch = oldfetch }

end

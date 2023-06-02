local gen = require("santoku.gen")
local vec = require("santoku.vector")
local tup = require("santoku.tuple")
local js = require("santoku.web.js")
local window = js.window
local JSON = window.JSON
local console = window.console
local Request = window.Request
local Promise = window.Promise

return function (callback, window)

  local oldwinerr = window and window.onerror
  local oldfetch = window and window.fetch
  local logtypes = vec("log", "error")
  local oldlogs = {}

  local function wrapLog (typ)
    if oldlogs[typ] then
      return
    end
    oldlogs[typ] = console[typ]
    console[typ] = function (_, ...)
      oldlogs.log(...)
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
    if window then
      window.onerror = function (...)
        callback(JSON:stringify({
          source = "error",
          args = vec(...)
        }))
        if oldwinerr then
          oldwinerr(console, ...)
        end
      end
    end
  end

  local function wrapFetch ()
    if window and oldfetch then
      window.fetch = function (_, r, ...)
        local args = tup(...)
        local req
        if type(r) == "string" or not r:instanceOf(Request) then
          req = Request:new(r, args())
        else
          req = r:clone()
        end
        return Promise:new(function (_, resolve)
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
            oldfetch(window, r, args()):await(function(_, ok, resp)
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
                resolve(nil, resp)
              end)
            end)
          end)
        end)
      end
    end
  end

  wrapErr()
  wrapLogs()
  wrapFetch()

  return { oldlogs = oldlogs }

end

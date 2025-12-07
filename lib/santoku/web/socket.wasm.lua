local js = require("santoku.web.js")
local val = require("santoku.web.val")
local str = require("santoku.string")
local global = js.self or js.global or js.window

return {
  fetch = function (url, opts, done)
    opts = opts or {}
    return global:fetch(url, val(opts, true)):await(function (_, ok, resp)
      if not ok then
        return done(false, resp)
      end
      local headers = {}
      if resp.headers then
        resp.headers:forEach(function (_, v, k)
          headers[str.lower(k)] = v
        end)
      end
      return done(resp.ok, {
        status = resp.status,
        headers = headers,
        ok = resp.ok,
        raw = resp,
        body = function (cb)
          return resp:text():await(function (_, ok, text)
            return cb(ok, text)
          end)
        end
      })
    end)
  end,
  sleep = function (ms, fn)
    return global:setTimeout(fn, ms)
  end
}

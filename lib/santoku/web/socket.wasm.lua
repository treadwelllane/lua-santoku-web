local js = require("santoku.web.js")
local val = require("santoku.web.val")
local str = require("santoku.string")
local global = js.self or js.global or js.window

local valid_fetch_opts = {
  method = true, headers = true, body = true, mode = true,
  credentials = true, cache = true, redirect = true, referrer = true,
  referrerPolicy = true, integrity = true, keepalive = true, signal = true
}

local function filter_opts (opts)
  local result = {}
  for k, v in pairs(opts) do
    if valid_fetch_opts[k] then
      result[k] = v
    end
  end
  return result
end

return {
  fetch = function (url, opts, done)
    opts = opts or {}
    local fetch_opts = filter_opts(opts)
    return global:fetch(url, val(fetch_opts, true)):await(function (_, ok, resp)
      if not ok then
        return done(false, { status = 0, headers = {}, ok = false, error = resp })
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

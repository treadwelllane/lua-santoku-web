local js = require("santoku.web.js")
local val = require("santoku.web.val")
local str = require("santoku.string")
local global = js.self or js.global or js.window
local Promise = js.Promise

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
  fetch = function (url, opts)
    opts = opts or {}
    local fetch_opts = filter_opts(opts)
    local ok, resp = global:fetch(url, val(fetch_opts, true)):await()
    if not ok then
      return false, { status = 0, headers = {}, ok = false, error = resp }
    end
    local headers = {}
    if resp.headers then
      resp.headers:forEach(function (_, v, k)
        headers[str.lower(k)] = v
      end)
    end
    return resp.ok, {
      status = resp.status,
      headers = headers,
      ok = resp.ok,
      raw = resp,
      body = function ()
        local ok, text = resp:text():await()
        if ok then
          return text
        end
        return nil
      end
    }
  end,
  sleep = function (ms)
    Promise:new(function (this, resolve)
      global:setTimeout(function ()
        resolve(this)
      end, ms)
    end):await()
  end
}

local js = require("santoku.web.js")
local val = require("santoku.web.val")
local err = require("santoku.error")
local arr = require("santoku.array")
local fun = require("santoku.functional")
local utc = require("santoku.utc")
local num = require("santoku.num")

local Promise = js.Promise
local global = js.self or js.global or js.window
local localStorage = global.localStorage
local Date = js.Date
local WebSocket = js.WebSocket
local Headers = js.Headers
local Response = js.Response

local M = {}

M.set_timeout = function (fn, ms, ...)
  return global:setTimeout(fn, ms, ...)
end

M.clear_timeout = function (id)
  return global:clearTimeout(id)
end

M.ws = function (url, opts, each, retries, backoffs)
  local data
  if type(url) ~= "string" then
    data = url.data
    each = url.each
    retries = url.retries
    backoffs = url.backoffs
    url = url.url
  elseif opts then
    data = opts
    retries = retries or opts.retries
    backoffs = backoffs or opts.backoffs
  end
  retries = retries or 3
  backoffs = backoffs or 1
  each = each or fun.noop
  local finalized = false
  local ws = nil
  local retry = 1
  local buffer = {}
  local function reconnect (url)
    local ws0 = WebSocket:new(url)
    ws0:addEventListener("open", function ()
      if finalized then
        return
      end
      ws = ws0
      if data then
        ws0:send(val.bytes(data))
      end
      for i = 1, #buffer do
        ws0:send(val.bytes(buffer[i]))
      end
      arr.clear(buffer)
    end)
    ws0:addEventListener("message", function (_, ev)
      local async = require("santoku.web.async")
      async(function ()
        local text = ev.data:text():await()
        each("message", text)
      end)
    end)
    ws0:addEventListener("close", function (_, ev)
      if finalized then
        return
      end
      ws = nil
      retry = retry + 1
      if retry > retries then
        each("close", ev.code, ev.reason, ev)
        finalized = true
        buffer = nil
      else
        each("reconnect", ev.code, ev.reason, ev)
        M.set_timeout(function ()
          return reconnect(url)
        end, backoffs * 1000)
      end
    end)
    ws0:addEventListener("error", function (_, ev)
      if finalized then
        return
      end
      if ev.code or ev.reason then
        each("error", ev.code, ev.reason, ev)
      end
    end)
  end
  reconnect(url)
  return function (data)
    if finalized then
      return err.error("websocket already closed")
    elseif not ws then
      arr.push(buffer, data)
    else
      ws:send(val.bytes(data))
    end
  end, function ()
    finalized = true
    if ws then
      ws:close()
      ws = nil
    end
  end
end

M.promise = function (fn)
  return Promise:new(function (this, resolve, reject)
    return fn(function (ok, ...)
      if not ok then
        return reject(this, ...)
      else
        return resolve(this, ...)
      end
    end)
  end)
end

M.never = function ()
  return Promise:new(function () end)
end

M.resolved = function (...)
  local args = { ... }
  return Promise:new(function (this, resolve)
    resolve(this, arr.spread(args))
  end)
end

M.rejected = function (...)
  local args = { ... }
  return Promise:new(function (this, _, reject)
    reject(this, arr.spread(args))
  end)
end

M.after_frame = function (fn)
  return global:requestAnimationFrame(function ()
    return global:requestAnimationFrame(fn)
  end)
end

M.throttle = function (fn, time)
  local last
  return function (...)
    local now = utc.time(true) * 1000
    if not last or (now - last) >= time then
      last = now
      return fn(...)
    end
  end
end

M.debounce = function (fn, time)
  local timer
  return function (...)
    M.clear_timeout(timer)
    timer = M.set_timeout(fn, time, ...)
  end
end

M.atleast = function (fn, min_ms)
  return function (...)
    local start = utc.time(true)
    local results = { fn(...) }
    local elapsed = (utc.time(true) - start) * 1000
    local remaining = min_ms - elapsed
    if remaining > 0 then
      Promise:new(function (this, resolve)
        M.set_timeout(function () resolve(this) end, remaining)
      end):await()
    end
    return arr.spread(results)
  end
end

M.component = function (tag, callback)
  if not callback then
    callback = tag
    tag = nil
  end
  local class = val.class(function (proto)
    proto.connectedCallback = callback
  end, js.window.HTMLElement)
  if tag then
    js.window.customElements:define(tag, class)
  end
  return class
end

M.set_local = function (k, v)
  if localStorage then
    if v == nil then
      return localStorage:removeItem(tostring(k))
    else
      return localStorage:setItem(tostring(k), tostring(v))
    end
  end
end

M.get_local = function (k)
  if localStorage then
    return localStorage:getItem(tostring(k))
  end
end

M.utc_date = function (seconds)
  local date = Date:new(0)
  date:setUTCSeconds(seconds)
  return date
end

M.date_utc = function (date)
  return num.trunc(date:getTime() / 1000, 0)
end

M.request_text = function (request)
  local ok, text = err.pcall(function ()
    return request:text():await()
  end)
  return ok and text or nil
end

M.request_json = function (request)
  local json = require("cjson")
  local text = M.request_text(request)
  if text then
    local ok, data = pcall(json.decode, text)
    return ok and data or nil
  end
  return nil
end

M.request_formdata = function (request)
  local str = require("santoku.string")
  local text = M.request_text(request)
  if text then
    return str.from_formdata(text)
  end
  return {}
end

M.response = function (body, opts)
  opts = opts or {}
  local headers = Headers:new()
  if opts.content_type then
    headers:set("Content-Type", opts.content_type)
  end
  if opts.headers then
    for k, v in pairs(opts.headers) do
      headers:set(k, v)
    end
  end
  return Response:new(body, {
    status = opts.status or 200,
    headers = headers
  })
end

return M

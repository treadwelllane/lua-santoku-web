local js = require("santoku.web.js")
local val = require("santoku.web.val")
local rand = require("santoku.random")
local err = require("santoku.error")
local async = require("santoku.async")
local str = require("santoku.string")
local arr = require("santoku.array")
local fun = require("santoku.functional")
local utc = require("santoku.utc")
local num = require("santoku.num")
local json = require("cjson")

local Promise = js.Promise
local global = js.self or js.global or js.window
local localStorage = global.localStorage
local Date = js.Date
local WebSocket = js.WebSocket
local AbortController = js.AbortController

local M = {}

M.set_timeout = function (fn, ms, ...)
  return global:setTimeout(fn, ms, ...)
end

M.clear_timeout = function (id)
  return global:clearTimeout(id)
end

local reqs = setmetatable({}, { __mode = "k" })

local function fetch_request (req)
  local url, method, headers = req.url, req.method, req.headers
  local signal = req.ctrl and req.ctrl.signal or nil
  local body, params
  if method == "GET" and req.qstr then
    url = url .. req.qstr
  end
  if method == "GET" and req.params then
    params = req.params
  end
  if method == "POST" and req.body then
    body = json.encode(req.body)
  end
  return M.fetch(url, {
    method = method,
    headers = headers,
    body = body,
    params = params,
    signal = signal,
    cache = req.cache,
  }, req)
end

M.request = function (url, opts, done, retry, raw)
  if url and reqs[url] then
    return url
  end
  local req = {}
  reqs[req] = true
  if type(url) ~= "string" then
    req.url = url.url
    req.body = url.body
    req.params = url.params
    req.headers = url.headers
    req.done = done or url.done
    req.retry = retry or url.retry
    req.raw = raw or url.raw
    req.cache = url.cache
  elseif opts then
    req.url = url
    req.body = opts.body
    req.params = opts.params
    req.headers = opts.headers
    req.done = done or url.done
    req.retry = retry or opts.retry
    req.raw = raw or opts.raw
    req.cache = opts.cache
  end
  req.qstr = req.params and str.to_query(req.params) or ""
  req.done = req.done or done or fun.noop
  req.events = async.events()
  req.ctrl = AbortController:new()
  req.retry = req.retry == nil and {} or req.retry
  if req.retry then
    local retry = type(req.retry) == "table" and req.retry or {}
    local times = retry.times or 3
    local backoff = retry.backoff or 1
    local multiplier = retry.multiplier or 3
    local filter = retry.filter or function (ok, resp)
      local s = resp and resp.status
      return not ok and (s == 502 or s == 503 or s == 504 or s == 429)
    end
    req.events.on("response", function (k, ...)
      if times > 0 and filter(...) then
        return M.set_timeout(function ()
          times = times - 1
          backoff = backoff * multiplier
          return fetch_request(req)
        end, (backoff + (backoff * rand.num())) * 1000)
      else
        return k(...)
      end
    end, true)
  end
  req.cancel = function ()
    return req.ctrl:abort()
  end
  return req
end

M.response = function (done, ok, resp, ...)
  local result = { ok = ok and resp.ok, status = resp.status }
  if resp.headers then
    result.headers = {}
    resp.headers:forEach(function (_, v, k)
      result.headers[str.lower(k)] = v
    end)
  end
  local ct = result.headers and result.headers["content-type"]
  if ct and str.find(ct, "application/json") then
    return resp:text():await(function (_, ok0, data, ...)
      if ok0 then
        result.body = json.decode(data)
        return done(result.ok, result)
      else
        return done(ok0, data, ...)
      end
    end)
  elseif resp and resp.text then
    return resp:text():await(function (_, ok0, data, ...)
      if ok0 then
        result.body = data
        return done(result.ok, result)
      else
        return done(ok0, data, ...)
      end
    end)
  else
    return done(result.ok, result, ...)
  end
end

M.fetch = function (url, opts, req)
  return global:fetch(url, val(opts, true)):await(function (_, ok, resp, ...)
    if not ok and resp and resp.name == "AbortError" then
      return
    end
    if req.raw then
      if req.events then
        return req.events.process("response", nil, req.done, ok, resp, ...)
      else
        return req.done(ok, resp, ...)
      end
    end
    return M.response(function (...)
      if req.events then
        return req.events.process("response", nil, req.done, ...)
      else
        return req.done(...)
      end
    end, ok, resp, ...)
  end)
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
      ev.data:text():await(function (_, ...)
        each("message", err.checkok(...))
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

M.get = function (...)
  local req = M.request(...)
  req.method = "GET"
  fetch_request(req)
  return req.cancel
end

M.post = function (...)
  local req = M.request(...)
  req.method = "POST"
  req.headers = req.headers or {}
  req.headers["content-type"] = req.headers["content-type"] or "application/json"
  fetch_request(req)
  return req.cancel
end

local intercept = function (fn, events)
  local req
  return function (...)
    events.process("request", nil, function (req0)
      req = req0
      req0.events.on("response", function (done0, ok0, ...)
        return events.process("response", function (done1, ok1, req1, ...)
          if ok1 == "retry" then
            return fn(req0)
          else
            return done1(ok1, req1, ...)
          end
        end, function (ok2, _, ...)
          return done0(ok2, ...)
        end, ok0, req0, ...)
      end, true)
      return fn(req0)
    end, M.request(...))
    return function ()
      if req then
        return req.cancel()
      end
    end
  end
end

M.http_client = function ()
  local events = async.events()
  return {
    on = events.on,
    off = events.off,
    get = intercept(M.get, events),
    post = intercept(M.post, events)
  }
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

return M

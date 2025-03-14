local js = require("santoku.web.js")
local val = require("santoku.web.val")
local rand = require("santoku.random")
local num = require("santoku.num")
local err = require("santoku.error")
local async = require("santoku.async")
local str = require("santoku.string")
local varg = require("santoku.varg")
local arr = require("santoku.array")
local tbl = require("santoku.table")
local it = require("santoku.iter")
local fun = require("santoku.functional")
local json = require("cjson")

local document = js.document
local Array = js.Array
local Promise = js.Promise
local global = js.self or js.global or js.window
local localStorage = global.localStorage
local Date = js.Date
local WebSocket = js.WebSocket
local AbortController = js.AbortController

local M = {}

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
  }, req)
end

-- TODO: consider retry-after header
-- TODO: lowercase headers?
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
  elseif opts then
    req.url = url
    req.body = opts.body
    req.params = opts.params
    req.headers = opts.headers
    req.done = done or url.done
    req.retry = retry or opts.retry
    req.raw = raw or opts.raw
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
      -- Should 408 (request timeout) be included?
      return not ok and (s == 502 or s == 503 or s == 504 or s == 429)
    end
    req.events.on("response", function (k, ...)
      if times > 0 and filter(...) then
        return global:setTimeout(function ()
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
        global:setTimeout(function ()
          return reconnect(url)
        end, backoffs * 1000)
      end
    end)
    ws0:addEventListener("error", function (_, ev)
      if finalized then
        return
      end
      -- Does it make sense to hide these errors?
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
    -- TODO: Does this prevent final close events from triggering? Should it?
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

-- TODO: extend to support ws
-- TODO: allow match/on_request for intercepting pre-request
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

M.clone = function (template, data, parent, before, pre_append)
  local clone = template.content:cloneNode(true)
  local el, els
  if data == nil then
    el = clone.firstElementChild
  else
    el, els = M.populate(clone.firstElementChild, data)
  end
  if pre_append then
    pre_append(el)
  end
  if parent then
    if before then
      parent:insertBefore(el, before)
    else
      parent:append(el)
    end
  end
  return el, els
end

M.after_frame = function (fn)
  return global:requestAnimationFrame(function ()
    return global:requestAnimationFrame(fn)
  end)
end

local function clone_all (items, wait, done, set_timeout, events)
  if not items then
    set_timeout()
    events.emit("done")
    done()
    return
  end
  local parent, before, template, data, map_data, map_el = items()
  if not parent then
    set_timeout()
    events.emit("done")
    done()
    return
  end
  if map_data then
    local data0 = map_data(data)
    if data0 == false then
      set_timeout()
      events.emit("done")
      done()
      return
    elseif data0 ~= nil then
      data = data0
    end
  end
  local el, els = M.clone(template, data)
  return events.process("cloned-element", nil, function (el)
    if map_el then
      local el0 = map_el(el, data, function (opts)
        items = it.chain(opts.items or it.map(function (data)
          return
            opts.parent,
            opts.before,
            opts.template,
            data,
            opts.map_data,
            opts.map_el
        end, it.ivals(opts.data)), items)
      end, els)
      if el0 == false then
        set_timeout()
        events.emit("done")
        done()
        return
      elseif el0 ~= nil then
        el = el0
      end
    end
    if before then
      parent:insertBefore(el, before)
    else
      parent:append(el)
    end
    return set_timeout(global:setTimeout(function ()
      clone_all(items, wait, done, set_timeout, events)
    end, wait))
  end, el)
end

M.clone_all = function (opts)
  local events = async.events()
  opts = opts or {}
  local timeout
  local function set_timeout (t)
    timeout = t
  end
  set_timeout(global:setTimeout(function ()
    clone_all(
      opts.items or it.map(function (data)
        return
          opts.parent,
          opts.before,
          opts.template,
          data,
          opts.map_data,
          opts.map_el
      end, it.ivals(opts.data)),
      opts.wait or 0,
      opts.done or function () end,
      set_timeout,
      events)
  end, 0))
  return function ()
    if timeout then
      global:clearTimeout(timeout)
      timeout = nil
    end
  end, events
end

local function parse_attr_value (data, attr, attrs, root)

  if not data then
    return ""
  end

  if attr.value == "" then
    return data or ""
  end

  if attr.value and data[attr.value] and data[attr.value] ~= "" then
    return data[attr.value]
  elseif data and type(attr.value) == "string" then
    local key = it.collect(str.gmatch(attr.value, "[^.]+"))
    local v
    if key[1] == "$" then
      v = tbl.get(root, varg.sel(2, arr.spread(key)))
    else
      v = tbl.get(data, arr.spread(key))
    end
    if v then
      return v or ""
    end
  end

  local def = attrs and attrs:getNamedItem(attr.name .. "-default")

  if def and def.value then
    return def.value
  else
    return ""
  end

end

local function check_attr_match (data, root, key, val)
  if key == nil then
    return
  end
  if type(val) == "table" then
    return arr.find(val, function (val)
      return check_attr_match(data, root, key, val)
    end) ~= nil
  end
  if key[1] == "$" then
    data = tbl.get(root, varg.sel(2, arr.spread(key)))
  else
    data = tbl.get(data, arr.spread(key))
  end
  return
    (val == "true" and data == true) or
    (val == "false" and data == false) or
    (val == "nil" and data == nil) or
    (val == nil and (data and data ~= "")) or
    (val ~= nil and val == data)
end

local function parse_attr_show_hide (attr)
  local show_hide, show_spec = str.match(attr.name, "^tk%-([^:]+)(.*)$")
  if show_hide ~= "show" and show_hide ~= "hide" then
    return
  end
  local show_key, show_val, show_attr = it.spread(str.gmatch(show_spec, ":([^:]+)"))
  show_key = it.collect(str.gmatch(show_key, "[^%.]+"))
  if show_val and str.match(show_val, "^%b[]$") then
    show_val = it.collect(str.gmatch(str.sub(show_val, 2, #show_val - 1), "[^,]+"))
  elseif show_val then
    show_val = { show_val }
  end
  if attr.value and attr.value ~= "" then
    return show_hide, show_key, show_val, show_attr, attr.value
  else
    return show_hide, show_key, show_val
  end
end

M.populate = function (el, data, root, els)

  els = els or {}
  data = data or {}
  root = root or data

  local recurse = true

  if el.hasAttributes and el:hasAttributes() then

    local add_attrs = {}
    local shadow, remove, repeat_, repeat_map_, repeat_done_

    Array:from(el.attributes):forEach(function (_, attr)
      if attr.name == "tk-repeat" then
        el:removeAttribute(attr.name)
        repeat_ = attr
        repeat_map_ = el:getAttributeNode("tk-repeat-map")
        repeat_done_ = el:getAttributeNode("tk-repeat-done")
        if repeat_map_ then
          repeat_map_ = parse_attr_value(data, repeat_map_, el.attributes, root)
          el:removeAttribute("tk-repeat-map")
        end
        if repeat_done_ then
          repeat_done_ = parse_attr_value(data, repeat_done_, el.attributes, root)
          el:removeAttribute("tk-repeat-done")
        end
        return
      end
      if attr.name == "tk-shadow" then
        el:removeAttribute(attr.name)
        shadow = (attr.value and attr.value ~= "") and attr.value or "closed"
        return
      end
      local show_hide, show_key, show_val, show_attr, show_exp =
        parse_attr_show_hide(attr)
      if show_hide == nil then
        return
      end
      -- TODO: safe to remove this ahead of time?
      el:removeAttribute(attr.name)
      if show_attr == nil then
        remove =
          (show_hide == "show" and not check_attr_match(data, root, show_key, show_val)) or
          (show_hide == "hide" and check_attr_match(data, root, show_key, show_val))
        return
      elseif
        (show_hide == "show" and check_attr_match(data, root, show_key, show_val)) or
        (show_hide == "hide" and not check_attr_match(data, root, show_key, show_val))
      then
        arr.push(add_attrs, { name = show_attr, value = show_exp })
        return
      end
    end)

    if remove then
      el:remove()
      return
    end

    for i = 1, #add_attrs do
      local a = add_attrs[i]
      local a0 = el:getAttribute(a.name)
      if a0 then
        el:setAttribute(a.name, arr.concat({ a0, a.value }, " "))
      else
        el:setAttribute(a.name, a.value)
      end
    end

    if repeat_ then

      recurse = false

      local el_before = el.nextSibling

      local ik = it.collect(str.gmatch(repeat_.value, "[^.]+"))
      local items = tbl.get(data, arr.spread(ik))

      if items then
        for i = 1, #items do
          local r0 = el:cloneNode(true)
          local item = items[i]
          if repeat_map_ then
            local r1 = repeat_map_(r0, item, i)
            if r1 ~= nil then
              r0 = r1
            end
          end
          M.populate(r0, item, root, els)
          el.parentNode:insertBefore(r0, el_before)
        end
      end

      if repeat_done_ then
        repeat_done_(items)
      end

      el:remove()

    else

      Array:from(el.attributes):forEach(function (_, attr)
        el:setAttribute(attr.name, str.interp(attr.value, data))
      end)

      local target = shadow and el:attachShadow({ mode = shadow }) or el

      Array:from(el.attributes):forEach(function (_, attr)
        if attr.name == "tk-id" then
          local ik = it.collect(str.gmatch(attr.value, "[^.]+"))
          arr.push(ik, el)
          tbl.set(els, arr.spread(ik))
          el:removeAttribute(attr.name)
        elseif str.match(attr.name, "^tk%-on%:") then
          local ev = str.sub(attr.name, 7, #attr.name)
          local fn = parse_attr_value(data, attr, el.attributes, root)
          -- TODO: allow passing true/false/etc to addEventListener and
          -- arbitrary arguments to the handler (maybe)
          if fn then
            el:addEventListener(ev, function (_, ev)
              return fn(ev, el)
            end)
          end
          el:removeAttribute(attr.name)
        elseif attr.name == "tk-text" then
          target:replaceChildren(document:createTextNode(parse_attr_value(data, attr, el.attributes, root)))
          el:removeAttribute(attr.name)
        elseif attr.name == "tk-html" then
          target.innerHTML = parse_attr_value(data, attr, el.attributes, root)
          el:removeAttribute(attr.name)
        elseif attr.name == "tk-href" then
          el.href = parse_attr_value(data, attr, el.attributes, root)
          el:removeAttribute(attr.name)
        elseif attr.name == "tk-value" then
          el.value = parse_attr_value(data, attr, el.attributes, root)
          el:removeAttribute(attr.name)
        elseif attr.name == "tk-src" then
          el.src = parse_attr_value(data, attr, el.attributes, root)
          el:removeAttribute(attr.name)
        elseif attr.name == "tk-checked" then
          el.checked = data[attr.value] or false
          el:removeAttribute(attr.name)
        end
      end)

    end

  end

  if recurse then

    Array:from(el.childNodes):forEach(function (_, node)
      if node.nodeType == 3 then -- text
        node.nodeValue = str.interp(node.nodeValue, data)
      end
    end)

    Array:from(el.children):forEach(function (_, child)
      M.populate(child, data, root, els)
    end)

  end

  return el, els, data

end

M.template = function (from)
  local el = document:createElement("template")
  if type(from) == "string" then
    el.innerHTML = from
  else
    el:append(from)
  end
  return el
end

M.static = function (str)
  return { template = M.template("<section><main>" .. str .. "</main></section>") }
end

M.throttle = function (fn, time)
  local last
  return function (...)
    local now = Date:now()
    if not last or (now - last) >= time then
      last = now
      return fn(...)
    end
  end
end

M.debounce = function (fn, time)
  local timer
  return function (...)
    global:clearTimeout(timer)
    timer = global:setTimeout(fn, time, ...)
  end
end

M.fit_image = function (e_img, e_main, image_ratio)
  if not image_ratio then
    image_ratio = e_img.width / e_img.height
  end
  local over_height = e_img.height - e_main.clientHeight
  local over_width = e_img.width - e_main.clientWidth
  if over_height > over_width then
    e_img.height = e_main.clientHeight
    e_img.width = e_img.height * image_ratio
  else
    e_img.width = e_main.clientWidth
    e_img.height = e_img.width / image_ratio
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

M.parse_path = function (url, path, params, modal)
  local result = { path = path or {}, params = params or {} }
  tbl.clear(result.path)
  tbl.clear(result.params)
  local path, query
  if url then
    path, query = str.match(url, "([^?]*)%??(.*)")
  end
  if path then
    for segment in str.gmatch(path, "[^/]+") do
      arr.push(result.path, segment)
    end
  end
  if modal and result.path[#result.path] then
    modal = str.sub(modal, 1, 1)
    local pat = "^([^%" .. modal .. "]*)%" .. modal .. "?(.*)$"
    local s, m = str.match(result.path[#result.path], pat)
    if s and m and m ~= "" then
      result.path[#result.path] = s
      result.modal = m
    end
  end
  if query then
    str.from_query(query, result.params)
  end
  return result
end

M.encode_path = function (t, params, modal)
  local out = {}
  for i = 1, #t.path do
    if type(t.path[i]) == "table" then
      break
    end
    arr.push(out, "/", str.from_url(t.path[i]))
  end
  if modal and t.modal then
    arr.push(out, modal, t.modal)
  end
  if (params or params == nil) and t.params and next(t.params) then
    str.to_query(t.params, out)
  end
  return arr.concat(out)
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

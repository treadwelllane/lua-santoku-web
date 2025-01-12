local js = require("santoku.web.js")
local val = require("santoku.web.val")
local err = require("santoku.error")
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

-- TODO: metatable on headers that lowercases keys
M.request = function (url, opts, done, retries, backoffs, retry_until, raw)
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
    req.retries = retries or url.retries
    req.backoffs = backoffs or url.backoffs
    req.retry_until = retry_until or url.retry_until
    req.raw = raw or url.raw
  elseif opts then
    req.url = url
    req.body = opts.body
    req.params = opts.params
    req.headers = opts.headers
    req.done = done or url.done
    req.retries = retries or opts.retries
    req.backoffs = backoffs or opts.backoffs
    req.retry_until = retry_until or opts.retry_until
    req.raw = raw or opts.raw
  end
  req.qstr = req.params and M.query_string(req.params) or ""
  req.done = req.done or done or fun.noop
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
        return done(ok, result)
      else
        return done(ok0, data, ...)
      end
    end)
  elseif resp and resp.text then
    return resp:text():await(function (_, ok0, data, ...)
      if ok0 then
        result.body = data
        return done(ok, result)
      else
        return done(ok0, data, ...)
      end
    end)
  else
    return done(ok, result, ...)
  end
end

M.fetch = function (url, opts, retries, backoffs, retry_until, raw, done)
  retries = retries or 3
  backoffs = backoffs or 1
  return global:fetch(url, val(opts, true)):await(function (_, ok, resp, ...)
    if not ok and resp and resp.name == "AbortError" then
      return
    end
    if raw then
      return done(true, resp, ...)
    end
    return M.response(function (ok, resp, ...)
      if ok and resp and resp.ok then
        return done(true, resp, ...)
      elseif retries <= 0 or (retry_until and retry_until(resp)) then
        return done(false, resp, ...)
      else
        return global:setTimeout(function ()
          return M.fetch(url, opts, retries - 1, backoffs, retry_until, raw, done)
        end, backoffs * 1000)
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
  local ctrl = AbortController:new()
  M.fetch(req.url .. req.qstr, {
    method = "GET",
    headers = req.headers,
    signal = ctrl.signal,
  }, req.retries, req.backoffs, req.retry_until, req.raw, req.done)
  return function ()
    return ctrl:abort()
  end
end

M.post = function (...)
  local req = M.request(...)
  req.headers = req.headers or {}
  req.headers["content-type"] = req.headers["content-type"] or "application/json"
  local ctrl = AbortController:new()
  M.fetch(req.url, {
    method = "POST",
    headers = req.headers,
    body = req.body and json.encode(req.body) or nil,
    signal = ctrl.signal,
  }, req.retries, req.backoffs, req.retry_until, req.raw, req.done)
  return function ()
    return ctrl:abort()
  end
end

local intercept = function (fn, opts)
  return function (...)
    if not opts.on_response then
      return fn(...)
    end
    local req = M.request(...)
    local retry_until = req.retry_until
    local done = req.done
    if opts.match_response then
      req.retry_until = function (resp, ...)
        return opts.match_response(false, req, resp, ...)
      end
    end
    req.done = function (ok, resp, ...)
      if opts.match_response and not opts.match_response(ok, req, resp, ...) then
        return done(ok, resp, ...)
      end
      return opts.on_response(function (result, ...)
        if result == "retry" then
          req.retry_until = retry_until
          req.done = done
          return M.get(req)
        else
          return done(ok, result, resp, ...)
        end
      end, ok, req, resp, ...)
    end
    return fn(req)
  end
end

-- TODO: extend to support ws
-- TODO: allow match/on_request for intercepting pre-request
M.http_client = function (opts)
  return {
    get = intercept(M.get, opts),
    post = intercept(M.post, opts)
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
  local el = M.populate(clone.firstElementChild, data)
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
  return el
end

M.after_frame = function (fn)
  return global:requestAnimationFrame(function ()
    global:requestAnimationFrame(fn)
  end)
end

local function clone_all (items, wait, done, set_timeout)
  if not items then
    done()
    return
  end
  local parent, before, template, data, map_data, map_el = items()
  if not parent then
    done()
    return
  end
  if map_data then
    if map_data(data) == false then
      done()
      return
    end
  end
  local el = M.clone(template, data)
  if map_el then
    if map_el(el, data, function (opts)
      items = it.chain(opts.items or it.map(function (data)
        return
          opts.parent,
          opts.before,
          opts.template,
          data,
          opts.map_data,
          opts.map_el
      end, it.ivals(opts.data)), items)
    end) == false then
      done()
      return
    end
  end
  if before then
    parent:insertBefore(el, before)
  else
    parent:append(el)
  end
  return set_timeout(global:setTimeout(function ()
    return clone_all(items, wait, done, set_timeout)
  end, wait))
end

M.clone_all = function (opts)
  opts = opts or {}
  local timeout
  local function set_timeout (t)
    timeout = t
  end
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
    set_timeout)
  return function ()
    if timeout then
      global:clearTimeout(timeout)
      timeout = nil
    end
  end
end

local function parse_attr_value (data, attr, attrs)

  if not data then
    return ""
  end

  if attr.value == "" then
    return data or ""
  end

  if attr.value and data[attr.value] and data[attr.value] ~= "" then
    return data[attr.value]
  elseif data and type(attr.value) == "string" then
    local v = tbl.get(data, arr.spread(it.collect(str.gmatch(attr.value, "[^.]+"))))
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

M.populate = function (el, data, root)

  root = root or data

  if not data then
    return el
  end

  local recurse = true

  if el.hasAttributes and el:hasAttributes() then

    local add_attrs = {}
    local shadow, remove, repeat_

    Array:from(el.attributes):forEach(function (_, attr)
      if attr.name == "tk-repeat" then
        el:removeAttribute(attr.name)
        repeat_ = attr
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

    Array:from(el.attributes):forEach(function (_, attr)
      el:setAttribute(attr.name, str.interp(attr.value, data))
    end)

    if repeat_ then

      recurse = false

      local el_before = el.nextSibling

      local ik = it.collect(str.gmatch(repeat_.value, "[^.]+"))
      local items = tbl.get(data, arr.spread(ik))

      if items then
        for i = 1, #items do
          local r0 = el:cloneNode(true)
          local item = items[i]
          M.populate(r0, item, root)
          el.parentNode:insertBefore(r0, el_before)
          el_before = r0
        end
      end

      el:remove()

    else

      local target = shadow and el:attachShadow({ mode = shadow }) or el

      Array:from(el.attributes):forEach(function (_, attr)
        if attr.name == "tk-text" then
          target:replaceChildren(document:createTextNode(parse_attr_value(data, attr, el.attributes)))
          el:removeAttribute(attr.name)
        elseif attr.name == "tk-html" then
          target.innerHTML = parse_attr_value(data, attr, el.attributes)
          el:removeAttribute(attr.name)
        elseif attr.name == "tk-href" then
          el.href = parse_attr_value(data, attr, el.attributes)
          el:removeAttribute(attr.name)
        elseif attr.name == "tk-value" then
          el.value = parse_attr_value(data, attr, el.attributes)
          el:removeAttribute(attr.name)
        elseif attr.name == "tk-src" then
          el.src = parse_attr_value(data, attr, el.attributes)
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
      M.populate(child, data, root)
    end)

  end

  return el

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

M.parse_query = function (query, out)
  out = out or {}
  for param, value in str.gmatch(query, "([^&=?]+)=([^&=?]+)") do
    param = js:decodeURIComponent(param)
    value = js:decodeURIComponent(value)
    param = tonumber(param) or param
    value = tonumber(value) or value
    out[param] = value
  end
  return out
end

M.query_string = function (data, out)
  local should_concat = out == nil
  out = out or {}
  arr.push(out, "?")
  local ks = it.collect(it.keys(data))
  arr.sort(ks)
  for k in it.vals(ks) do
    local v = data[k]
    arr.push(out, js:encodeURIComponent(k), "=", js:encodeURIComponent(v), "&")
  end
  out[#out] = nil
  if should_concat then
    return arr.concat(out)
  else
    return out
  end
end

M.parse_path = function (url, path, params)
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
  if result.path[#result.path] then
    local s, m = str.match(result.path[#result.path], "^([^%$]*)%$?(.*)$")
    if s and m and m ~= "" then
      result.path[#result.path] = s
      result.modal = m
    end
  end
  if query then
    M.parse_query(query, result.params)
  end
  return result
end

M.encode_path = function (t, params)
  local out = {}
  for i = 1, #t.path do
    if type(t.path[i]) == "table" then
      break
    end
    arr.push(out, "/", js:decodeURIComponent(t.path[i]))
  end
  if t.modal then
    arr.push(out, "$", t.modal)
  end
  if (params or params == nil) and t.params and next(t.params) then
    M.query_string(t.params, out)
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

return M

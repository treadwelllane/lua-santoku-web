local js = require("santoku.web.js")
local val = require("santoku.web.val")
local err = require("santoku.error")
local str = require("santoku.string")
local arr = require("santoku.array")
local tbl = require("santoku.table")
local it = require("santoku.iter")
local fun = require("santoku.functional")

local history = js.history
local document = js.document
local Array = js.Array
local Promise = js.Promise
local global = js.self or js.global or js.window
local localStorage = global.localStorage
local JSON = js.JSON
local WebSocket = js.WebSocket
local AbortController = js.AbortController

local M = {}

M.fetch = function (url, opts, retries, backoffs)
  retries = retries or 3
  backoffs = backoffs or 1
  return M.promise(function (complete)
    return global:fetch(url, opts):await(function (_, ok, resp)
      if not ok and resp and resp.name == "AbortError" then
        return
      end
      if ok and resp and resp.ok then
        return complete(true, resp)
      elseif retries <= 0 then
        return complete(false, resp)
      else
        return global:setTimeout(function ()
          return M.fetch(url, opts, retries - 1, backoffs)
            :await(fun.sel(complete, 2))
        end, backoffs * 1000)
      end
    end)
  end)
end

-- TODO: retry/backoff on connection dropped
M.ws = function (url, params, each, retries, backoffs)
  if type(url) ~= "string" then
    params = url.params
    each = url.each
    retries = url.retries
    backoffs = url.backoffs
    url = url.url
  end
  local qstr = params and M.query_string(params) or ""
  each = each or fun.noop
  local ws = WebSocket:new(url .. qstr)
  ws:addEventListener("message", function (_, ev)
    each("message", ev.data, ev)
  end)
  ws:addEventListener("close", function (_, ev)
    ws = nil
    each("close", ev.code, ev.reason, ev)
  end)
  ws:addEventListener("error", function (_, ev)
    each("error", ev)
  end)
  return function (data)
    if not ws then
      return err.error("websocket already closed")
    end
    return ws:send(data)
  end, function ()
    if ws then
      ws:close()
      ws = nil
    end
  end
end

M.get = function (url, params, done, retries, backoffs)
  local headers = nil
  if type(url) ~= "string" then
    params = url.params
    headers = url.headers
    done = url.done
    retries = url.retries
    backoffs = url.backoffs
    url = url.url
  end
  local qstr = params and M.query_string(params) or ""
  done = done or fun.noop
  local ctrl = AbortController:new()
  M.fetch(url .. qstr, {
    method = "GET",
    headers = headers,
    signal = ctrl.signal,
  }, retries, backoffs):await(function (_, ok, resp, ...)
    if not ok then
      return done(false, "request error", resp.ok, resp.status, resp, ...)
    elseif not resp.ok then
      return done(false, "bad status", resp.ok, resp.status)
    else
      local ct = resp.headers:get("content-type")
      if ct and str.find(ct, "application/json") then
        return resp:json():await(fun.sel(done, 2))
      else
        return resp:text():await(fun.sel(done, 2))
      end
    end
  end)
  return function ()
    return ctrl:abort()
  end
end

M.post = function (url, body, done, retries, backoffs)
  local headers = nil
  if type(url) ~= "string" then
    body = url.body
    headers = url.headers
    done = url.done
    retries = url.retries
    backoffs = url.backoffs
    url = url.url
  end
  done = done or fun.noop
  headers = headers or {}
  headers["Content-Type"] = headers["Content-Type"] or "application/json"
  local ctrl = AbortController:new()
  M.fetch(url, {
    method = "POST",
    headers = headers,
    body = body and JSON:stringify(body) or nil,
    signal = ctrl.signal,
  }, retries, backoffs):await(function (_, ok, resp, ...)
    if not ok then
      return done(false, "request error", url, resp, ...)
    elseif not resp.ok then
      return done(false, "bad status", url, resp.ok, resp.status)
    else
      local ct = resp.headers:get("content-type")
      if ct and str.find(ct, "application/json") then
        return resp:json():await(fun.sel(done, 2))
      else
        return resp:text():await(fun.sel(done, 2))
      end
    end
  end)
  return function ()
    return ctrl:abort()
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

M.forward = function (path, state, replace)
  state = val(state, true)
  if replace then
    history:replaceState(state, nil, path)
  else
    history:pushState(state, nil, path)
  end
  history:go()
end

M.backward = function ()
  history:back()
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
    map_data(data)
  end
  local el = M.clone(template, data)
  if map_el then
    map_el(el, data, function (opts)
      items = it.chain(opts.items or it.map(function (data)
        return
          opts.parent,
          opts.before,
          opts.template,
          data,
          opts.map_data,
          opts.map_el
      end, it.ivals(opts.data)), items)
    end)
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

local function check_attr_match (data, key, val)
  if key == nil then
    return
  end
  if type(val) == "table" then
    return arr.find(val, function (val)
      return check_attr_match(data, key, val)
    end) ~= nil
  end
  data = data[key]
  return
    (val == "true" and data == true) or
    (val == "false" and data == false) or
    (val == "nil" and data == nil) or
    (val == nil and (data and data ~= "")) or
    (val ~= nil and val == data)
end

-- data-show:ok
-- data-show:ok:true
-- data-show:ok:nil
-- data-show.class:ok:true
-- data-show.class:ok:nil
local function parse_attr_show_hide (attr)
  local show_hide, show_spec = str.match(attr.name, "^data%-([^:]+)(.*)$")
  if show_hide ~= "show" and show_hide ~= "hide" then
    return
  end
  local show_key, show_val, show_attr = it.spread(str.gmatch(show_spec, ":([^:]+)"))
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

M.populate = function (el, data)

  if not data then
    return el
  end

  local recurse = true

  if el.hasAttributes and el:hasAttributes() then

    local add_attrs = {}
    local remove, repeat_

    Array:from(el.attributes):forEach(function (_, attr)
      if attr.name == "data-repeat" then
        el:removeAttribute(attr.name)
        repeat_ = attr
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
          (show_hide == "show" and not check_attr_match(data, show_key, show_val)) or
          (show_hide == "hide" and check_attr_match(data, show_key, show_val))
        return
      elseif
        (show_hide == "show" and check_attr_match(data, show_key, show_val)) or
        (show_hide == "hide" and not check_attr_match(data, show_key, show_val))
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

      for i = 1, #data[repeat_.value] do
        local r0 = el:cloneNode(true)
        M.populate(r0, data[repeat_.value][i])
        el.parentNode:insertBefore(r0, el_before)
        el_before = r0
      end

      el:remove()

    else

      Array:from(el.attributes):forEach(function (_, attr)
        if attr.name == "data-text" then
          el:replaceChildren(document:createTextNode(parse_attr_value(data, attr, el.attributes)))
          el:removeAttribute(attr.name)
        elseif attr.name == "data-html" then
          el.innerHTML = parse_attr_value(data, attr, el.attributes)
          el:removeAttribute(attr.name)
        elseif attr.name == "data-href" then
          el.href = parse_attr_value(data, attr, el.attributes)
          el:removeAttribute(attr.name)
        elseif attr.name == "data-value" then
          el.value = parse_attr_value(data, attr, el.attributes)
          el:removeAttribute(attr.name)
        elseif attr.name == "data-src" then
          el.src = parse_attr_value(data, attr, el.attributes)
          el:removeAttribute(attr.name)
        elseif attr.name == "data-checked" then
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
      M.populate(child, data)
    end)

  end

  return el

end

M.update = function (data, el)
  data = data or {}
  if el.dataset and el.dataset.prop then
    if el.type == "checkbox" then
      data[el.dataset.prop] = el.checked
    else
      data[el.dataset.prop] = el.value
    end
  end
  return data
end

M.data = function (el, ret)
  ret = ret or {}
  M.update(ret, el)
  Array:from(el.children):forEach(function (_, child)
    M.data(child, ret)
  end)
  return ret
end

M.clear = function (el)
  if el.dataset and (el.dataset.value or el.dataset.prop) then
    el.value = ""
  end
  if el.dataset and el.dataset.text then
    el.innerHTML = ""
  end
  Array:from(el.children):forEach(function (_, child)
    M.clear(child)
  end)
end

M.template = function (str)
  local el = document:createElement("template")
  el.innerHTML = str
  return el
end

M.static = function (str)
  return { template = M.template("<section><main>" .. str .. "</main></section>") }
end

-- TODO
M.throttle = function (--[[  fn, time  ]])
  error("throttle: unimplemented")
end

M.debounce = function (fn, time)
  local timer
  return function ()
    global:clearTimeout(timer)
    timer = global:setTimeout(fn, time)
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
  if query then
    M.parse_query(query, result.params)
  end
  return result
end

M.encode_path = function (t)
  local out = {}
  for i = 1, #t.path do
    arr.push(out, "/", js:decodeURIComponent(t.path[i]))
  end
  if t.params and next(t.params) then
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

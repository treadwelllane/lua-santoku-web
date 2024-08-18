local js = require("santoku.web.js")
local val = require("santoku.web.val")
local str = require("santoku.string")
local arr = require("santoku.array")
local fun = require("santoku.functional")

local history = js.history
local document = js.document
local Array = js.Array
local Promise = js.Promise
local global = js.self or js.global or js.window
local localStorage = global.localStorage
local JSON = js.JSON

local M = {}

-- TODO: Implement retry, backoff, etc
M.fetch = function (url, opts, retries, backoffs)
  retries = retries or 3
  backoffs = backoffs or 1
  return M.promise(function (complete)
    return global:fetch(url, opts):await(function (_, ok, resp)
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

M.get = function (url, params, done, retries, backoffs)
  done = done or fun.noop
  return M.fetch(url .. M.query_string(params), {
    method = "GET",
  }, retries, backoffs):await(function (_, ok, resp, ...)
    if not ok then
      return done(false, "request error", resp, ...)
    elseif not resp.ok then
      return done(false, "bad status", resp.ok, resp.status)
    else
      return resp:json():await(fun.sel(done, 2))
    end
  end)
end

M.post = function (url, body, done, retries, backoffs)
  done = done or fun.noop
  return M.fetch(url, {
    method = "POST",
    body = JSON:stringify(body)
  }, retries, backoffs):await(function (_, ok, resp, ...)
    if not ok then
      return done(false, "request error", url, resp, ...)
    elseif not resp.ok then
      return done(false, "bad status", url, resp.ok, resp.status)
    else
      return resp:json():await(fun.sel(done, 2))
    end
  end)
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

M.clone = function (tpl, data, parent)
  local clone = tpl.content:cloneNode(true)
  -- TODO: Should we use firstChild or just
  -- return the whole document fragment?
  local el =  M.populate(clone.firstElementChild, data)
  if parent then
    parent:append(el)
  end
  return el
end

local function clone_all (tpl, datas, parent, chunksize, wait, s, e)
  local frag = document:createDocumentFragment()
  for i = s, e do
    if i > #datas then
      return
    end
    M.clone(tpl, datas[i], frag)
  end
  parent:append(frag)
  global:setTimeout(function ()
    return clone_all(tpl, datas, parent, chunksize, wait, e + 1, e + chunksize)
  end, wait)
end

M.clone_all = function (tpl, datas, parent, chunksize, wait)
  chunksize = chunksize == true and #datas or chunksize or 10
  wait = wait or 10
  clone_all(tpl, datas, parent, chunksize, wait, 1, chunksize)
end

local function parse_attr_value (data, attr, attrs)

  if attr.value == "" then
    return data
  end

  if attr.value and data[attr.value] and data[attr.value] ~= "" then
    return data[attr.value]
  end

  local def = attrs:getNamedItem(attr.name .. "-default")

  if def then
    return def.value
  else
    return ""
  end

end

M.populate = function (el, data)

  if not data then
    return el
  end

  local recurse = true

  if el.hasAttributes and el:hasAttributes() then

    local attrs = Array:from(el.attributes)

    attrs:forEach(function (_, attr)
      -- TODO: This may cause some trouble for things that shouldn't be
      -- interpolated, like hrefs.
      attr.value = str.interp(attr.value, data)
    end)

    local repeat_ = attrs:find(function (_, attr)
      return attr.name == "data-repeat"
    end)

    if repeat_ then

      recurse = false

      local el_before = el.nextSibling

      for i = 1, #data[repeat_.value] do
        local r0 = el:cloneNode(true)
        r0:removeAttribute("data-repeat")
        M.populate(r0, data[repeat_.value][i])
        el.parentNode:insertBefore(r0, el_before)
        el_before = r0
      end

      el:remove()

    else

      attrs:forEach(function (_, attr)
        if attr.name == "data-text" then
          el:replaceChildren(document:createTextNode(parse_attr_value(data, attr, el.attributes)))
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

-- TODO
M.debounce = function (--[[  fn, time  ]])
  error("throttle: unimplemented")
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
  local class = val.class(function (proto)
    proto.connectedCallback = callback
  end, js.window.HTMLElement)
  js.window.customElements:define(tag, class)
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
  for k, v in pairs(data) do
    arr.push(out, js:encodeURIComponent(k), "=", js:encodeURIComponent(v), "&")
  end
  out[#out] = nil
  if should_concat then
    return arr.concat(out)
  else
    return out
  end
end

M.parse_path = function (url)
  local result = { path = {}, params = {} }
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

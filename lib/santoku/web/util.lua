local js = require("santoku.web.js")
local val = require("santoku.web.val")
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

M.get = function (url, params, done, retries, backoffs)
  done = done or fun.noop
  local ctrl = AbortController:new()
  M.fetch(url .. M.query_string(params), {
    method = "GET",
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
  done = done or fun.noop
  local ctrl = AbortController:new()
  M.fetch(url, {
    method = "POST",
    headers = { ["Content-Type"] = "application/json" },
    body = JSON:stringify(body),
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

    local show = attrs:find(function (_, attr)
      return attr.name == "data-show"
    end)

    local hide = attrs:find(function (_, attr)
      return attr.name == "data-hide"
    end)

    local repeat_ = attrs:find(function (_, attr)
      return attr.name == "data-repeat"
    end)

    if show then
      local v = parse_attr_value(data, show)
      if not v or v == "" then
        el:remove()
        return
      end
    end

    if hide then
      local v = parse_attr_value(data, hide)
      if v and v ~= "" then
        el:remove()
        return
      end
    end

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

local function pane_default (pages, name)
  if name == "default" then
    return pages.default
  else
    return name
  end
end

local function pane_wrap (page, name)
  local template
  if page.tagName == "TEMPLATE" then
    template = page
    page = {
      init = function (view, data)
        if data then
          util.populate(view.el, data)
        end
      end
    }
  else
    template = page.template
  end
  local sect = template and template.content and template.content.firstElementChild
  if (not sect) or sect.tagName ~= "SECTION" then
    page.template = wrap(sect and util.clone(template) or nil)
    return page
  end
  page.template = template
  return page
end

local function pane_page (pages, name)
  local page = pages[name]
  if page then
    return pane_wrap(page, name)
  end
end

local function init_pane (page, name)
  local pane = {
    page = page,
    name = name,
    state = state
  }

  view.toggle_nav = function ()
    return M.toggle_nav_state(active_view.active_view, not view.el.classList:contains("showing-nav"), true, true)
  end

  view.pane = function (name, page_name, ...)
    return M.pane(view, name, page_name, false, ...)
  end

  view.after_transition = M.after_transition
  view.after_frame = util.after_frame

  local clone_all_wrap_opts
  clone_all_wrap_opts = function (view, opts)
    return setmetatable({
      map_el = function (el, data, clone_all)
        M.setup_dynamic(view, el)
        if opts.map_el then
          return opts.map_el(el, data, function (opts0)
            return clone_all(clone_all_wrap_opts(view, opts0))
          end)
        end
      end
    }, { __index = opts })
  end

  view.clone_all = function (opts)
    return util.clone_all(clone_all_wrap_opts(view, opts))
  end

  view.clone = function (template, data, parent, before, pre_append)
    return util.clone(template, data, parent, before, function (el)
      M.setup_dynamic(view, el)
      if pre_append then
        return pre_append(el)
      end
    end)
  end

  return view

end

M.pane = function (el, pages, init, ...)
  local active
  local function switch (name, ...)
    local page = pane_page(pages, name)
    if active and page == active.page then
      return
    end
    local last = active
    active = { page = page, name = name }
    enter_pane(pane, active, last, true, ...)
    if last then
      exit_pane(last, active)
    end
  end
  switch(pane_default(pages, init), ...)
  return switch
end

return M

local js = require("santoku.web.js")
local str = require("santoku.string")

local window = js.window
local document = window.document
local location = window.location
local Array = window.Array

local M = {}

M.redirect = function (path)
  location.href = path
end

M.clone = function (tpl, data)
  local clone = tpl.content:cloneNode(true)
  -- TODO: Should we use firstChild or just
  -- return the whole document fragment?
  return M.populate(clone.firstElementChild, data)
end

M.populate = function (el, data)
  if not data then
    return el
  end
  if el.hasAttributes and el:hasAttributes() then
    Array:from(el.attributes):forEach(function (_, attr)
      attr.value = str.interp(attr.value, data)
      if attr.name == "data-text" then
        el:replaceChildren(document:createTextNode(data[attr.value] or ""))
      elseif attr.name == "data-value" then
        el.value = data[attr.value] or ""
      elseif attr.name == "data-checked" then
        el.checked = data[attr.value] or false
      end
    end)
  end
  Array:from(el.childNodes):forEach(function (_, node)
    if node.nodeType == 3 then -- text
      node.nodeValue = str.interp(node.nodeValue, data)
    end
  end)
  Array:from(el.children):forEach(function (_, child)
    M.populate(child, data)
  end)
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

return M

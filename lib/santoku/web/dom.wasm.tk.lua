<% build = require("santoku.make.build") %>
local val = require("santoku.web.val")
local dom = require("santoku.web.dom.buf")

local g = val.global("globalThis"):lua()

g:eval([==[<% return build.minify_js(readfile("res/web/dom.js")), false %>]==])

function dom.listen (id, event, fn, opts)
  local el
  if id == "window" then
    el = g.window
  elseif id == "body" then
    el = g.document.body
  else
    el = g.document:getElementById(id)
  end
  if not el then return end
  if opts then
    el:addEventListener(event, val(fn), val(opts, true))
  else
    el:addEventListener(event, val(fn))
  end
end

return dom
